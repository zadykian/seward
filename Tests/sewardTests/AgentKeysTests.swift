import CryptoKit
import Foundation
import Testing

@testable import seward

/// An answer's fields, read in turn as the ssh-agent protocol writes them.
struct AnswerFields {
    private var rest: Data

    init(_ answer: Data) {
        rest = answer
    }

    var isAtEnd: Bool { rest.isEmpty }

    mutating func byte() throws -> UInt8 {
        let byte = try #require(rest.first)
        rest = rest.dropFirst()
        return byte
    }

    mutating func uint32() throws -> UInt32 {
        let bytes = rest.prefix(4)
        try #require(bytes.count == 4)
        rest = rest.dropFirst(4)
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func string() throws -> Data {
        let count = Int(try uint32())
        try #require(rest.count >= count)
        defer { rest = rest.dropFirst(count) }
        return Data(rest.prefix(count))
    }
}

/// A key as the agent's answer to request 11 lists it.
struct ListedKey: Equatable {
    var blob: Data
    var name: String
}

@Suite struct AgentKeysTests {
    private let log = RecordingLog()
    private let data = Data("to sign".utf8)

    private func context(_ root: String, enclave: any Enclave = RecordingEnclave()) -> Context {
        Context(keys: KeyDirectory(path: root + "/.ssh"), enclave: enclave)
    }

    /// The keys that the agent's answer to request 11 lists: each one's blob and name.
    private func listed(by agent: Agent) throws -> [ListedKey] {
        var fields = AnswerFields(try agent.answer(Data([11])))
        let type = try fields.byte()
        #expect(type == 12)
        let count = try fields.uint32()
        var keys: [ListedKey] = []
        for _ in 0..<count {
            let blob = try fields.string()
            let name = try fields.string()
            keys.append(ListedKey(blob: blob, name: String(bytes: name, encoding: .utf8) ?? ""))
        }
        #expect(fields.isAtEnd)
        return keys
    }

    /// Asks the agent to sign `data` with the key of `blob`, and checks the answer against the key
    /// of the `.pub` line `pub`, as ssh would against the server's copy.
    private func signs(_ agent: Agent, with blob: Data, as pub: String) throws -> Bool {
        let request = Data([13]) + AgentWire.string(blob) + AgentWire.string(data) + AgentWire.uint32(0)
        var fields = AnswerFields(try agent.answer(request))
        let type = try fields.byte()
        try #require(type == 14)
        var signature = AnswerFields(try fields.string())
        let signatureType = try signature.string()
        #expect(signatureType == Data(SSHPublicKey.type.utf8))
        var numbers = AnswerFields(try signature.string())
        var raw = Data()
        for _ in 0..<2 {
            let number = try numbers.string()
            // OpenSSH refuses a zero byte before a number but for a sign bit.
            let signBit = number.dropFirst().first.map { $0 & 0x80 != 0 } ?? false
            #expect(number.first != 0 || signBit)
            let magnitude = number.drop { $0 == 0 }
            try #require(magnitude.count <= 32)
            raw += Data(count: 32 - magnitude.count) + magnitude
        }
        #expect(fields.isAtEnd && signature.isAtEnd && numbers.isAtEnd)
        let fieldsOfPub = pub.split(separator: " ")
        try #require(fieldsOfPub.count == 3)
        let blobOfPub = try #require(Data(base64Encoded: String(fieldsOfPub[1])))
        let key = try P256.Signing.PublicKey(x963Representation: blobOfPub.suffix(65))
        let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        return key.isValidSignature(ecdsa, for: data)
    }

    private func signsWithItsKeyAlone(store: Store, enclave: any Enclave) throws {
        try withTemporaryDirectory { root throws in
            let context = self.context(root, enclave: enclave)
            let pub = Cli.run(["keygen", "--store", store.rawValue, "work"], context: context).output
            let agent = Agent(context: context, log: log)
            let keys = try listed(by: agent)
            try #require(keys.count == 1)
            #expect(keys[0].name == "work")
            #expect(SSHPublicKey.type + " " + keys[0].blob.base64EncodedString() + " work\n" == pub)
            #expect(try signs(agent, with: keys[0].blob, as: pub))
            #expect(log.events == [.signed(name: "work")])
        }
    }

    @Test(arguments: Store.allCases)
    func aSignatureVerifiesAgainstTheKeysPublicFile(store: Store) throws {
        try signsWithItsKeyAlone(store: store, enclave: RecordingEnclave())
    }

    @Test(.enabled(if: SecureEnclave.isAvailable, "this Mac has no Secure Enclave"))
    func theSecureEnclavesKeySignsWithNobodyThere() throws {
        try signsWithItsKeyAlone(store: .enclave, enclave: SecureEnclaveChip())
    }

    @Test func aNewKeyIsServedWithNoRestart() throws {
        try withTemporaryDirectory { root throws in
            let context = self.context(root)
            let agent = Agent(context: context, log: log)
            #expect(try listed(by: agent).isEmpty)
            let pub = Cli.run(["keygen", "--store", "file", "work"], context: context).output
            let keys = try listed(by: agent)
            #expect(keys.map(\.name) == ["work"])
            let first = try #require(keys.first)
            #expect(try signs(agent, with: first.blob, as: pub))
        }
    }

    @Test func theKeysAreListedPastAKeyThatDoesNotLoad() throws {
        try withTemporaryDirectory { root throws in
            let context = self.context(root)
            let pub = Cli.run(["keygen", "--store", "file", "work"], context: context).output
            for (name, store) in [("another-mac", Store.enclave), ("broken", Store.file)] {
                let file = KeyFile(store: store, key: Data(repeating: 7, count: 10))
                try file.encoded().write(to: URL(fileURLWithPath: root + "/.ssh/" + name))
            }
            let agent = Agent(context: context, log: log)
            let keys = try listed(by: agent)
            #expect(keys.map(\.name) == ["work"])
            #expect(log.events.count == 2)
            for (event, name) in zip(log.events, ["another-mac", "broken"]) {
                guard case let .skipped(path, reason) = event else {
                    Issue.record("not a skip: \(event)")
                    continue
                }
                #expect(path == root + "/.ssh/" + name)
                #expect(reason.hasPrefix("its key does not load on this Mac: "))
            }
            let first = try #require(keys.first)
            #expect(try signs(agent, with: first.blob, as: pub))
        }
    }

    @Test func answerLoadsTheKeysThroughTheEnclaveItIsGiven() throws {
        try withTemporaryDirectory { root throws in
            let enclave = RecordingEnclave()
            let context = self.context(root, enclave: enclave)
            try #require(Cli.run(["keygen", "--store", "enclave", "work"], context: context).status == .success)
            let loads = enclave.loads
            var ends: [Int32] = [0, 0]
            try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &ends) == 0)
            defer { close(ends[0]) }
            try AgentCommand.send(AgentWire.framed(Data([AgentWire.requestIdentities])), to: ends[0], path: "pair")
            // The request is the connection's last, so that the agent answers it here and closes.
            shutdown(ends[0], SHUT_WR)
            AgentCommand.answer(ends[1], keys: context.keys, enclave: context.enclave, path: "pair")
            let answer = try AgentWire.nextMessage { try AgentCommand.receive(upTo: $0, from: ends[0], path: "pair") }
            var fields = AnswerFields(try #require(answer))
            let type = try fields.byte()
            let count = try fields.uint32()
            #expect(type == AgentWire.identitiesAnswer && count == 1)
            #expect(enclave.loads == loads + 1)
        }
    }
}
