import Foundation
import Testing

@testable import seward

/// What the agent's keys did: how often the agent read them, and what each signed.
final class KeyRecord {
    var reads = 0
    var signed: [Data] = []
}

/// A failure that a test makes, with the reason that the log gives.
struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@Suite struct AgentTests {
    private static let raw = Data(repeating: 1, count: 64)
    private let record = KeyRecord()
    private let log = RecordingLog()

    /// `work`, which signs, and `home`, which fails to.
    private static func keys(_ record: KeyRecord) -> [AgentKey] {
        [
            AgentKey(name: "work", blob: Data([1, 2])) { data in
                record.signed.append(data)
                return raw
            },
            AgentKey(name: "home", blob: Data([3])) { _ in throw TestFailure(description: "the enclave refused") },
        ]
    }

    private var agent: Agent {
        let record = record
        return Agent(keys: {
            record.reads += 1
            return Self.keys(record)
        }, log: log)
    }

    private let identities = AgentAnswer.identities(keys(KeyRecord()))

    private func signRequest(_ blob: Data, _ data: Data) -> Data {
        Data([13]) + AgentWire.string(blob) + AgentWire.string(data) + AgentWire.uint32(0)
    }

    @Test func aRequestForTheKeysListsThemAsTheyAreAtEachRequest() throws {
        #expect(try agent.answer(Data([11])) == identities)
        #expect(try agent.answer(Data([11])) == identities)
        #expect(record.reads == 2)
        #expect(log.events.isEmpty)
    }

    @Test func aSignRequestSignsWithTheKeyThatItsBlobNamesAndLogsIt() throws {
        let answer = try agent.answer(signRequest(Data([1, 2]), Data("to sign".utf8)))
        #expect(answer == AgentAnswer.signature(Self.raw))
        #expect(record.signed == [Data("to sign".utf8)])
        #expect(log.events == [.signed(name: "work")])
    }

    @Test func aSignRequestForAKeyNotHereFails() throws {
        #expect(try agent.answer(signRequest(Data([1]), Data("to sign".utf8))) == Data([5]))
        #expect(record.signed.isEmpty)
        #expect(log.events.isEmpty)
    }

    @Test func aKeyThatFailsToSignGetsAFailureAndItsReason() throws {
        #expect(try agent.answer(signRequest(Data([3]), Data("to sign".utf8))) == Data([5]))
        #expect(log.events == [.failed("the key home did not sign: the enclave refused")])
    }

    @Test func everyOtherRequestFailsSessionBindAmongThem() throws {
        let extensionName = AgentWire.string(Data("session-bind@openssh.com".utf8))
        #expect(try agent.answer(Data([27]) + extensionName + AgentWire.uint32(0)) == Data([5]))
        #expect(try agent.answer(Data([17])) == Data([5]))
        #expect(record.reads == 0)
    }

    @Test func aConnectionGetsAnAnswerToEachMessageInTurn() {
        let messages = AgentWire.framed(Data([11])) + AgentWire.framed(signRequest(Data([1, 2]), Data([9])))
        var written = Data()
        agent.serve(input: ClientBytes(messages, chunk: 3).read) { written += $0 }
        #expect(written == AgentWire.framed(identities) + AgentWire.framed(AgentAnswer.signature(Self.raw)))
        #expect(log.events == [.signed(name: "work")])
    }

    @Test(arguments: [
        (AgentWire.uint32(AgentWire.maximumLength + 1), AgentWireError.tooLong(AgentWire.maximumLength + 1)),
        (AgentWire.framed(Data([13, 0, 0, 0, 2, 1])), AgentWireError.cutShort),
        (AgentWire.framed(Data()), AgentWireError.cutShort),
    ] as [(Data, AgentWireError)])
    func aMessageThatBreaksTheFrameEndsTheConnectionAfterTheAnswersBefore(bad: Data, error: AgentWireError) {
        let client = ClientBytes(AgentWire.framed(Data([11])) + bad + AgentWire.framed(Data([11])))
        var written = Data()
        agent.serve(input: client.read) { written += $0 }
        #expect(written == AgentWire.framed(identities))
        #expect(log.events == [.failed("a connection closed: \(error)")])
    }

    @Test func aFailureToWriteEndsTheConnection() {
        let client = ClientBytes(AgentWire.framed(Data([11])) + AgentWire.framed(Data([11])))
        var writes = 0
        agent.serve(input: client.read) { _ in
            writes += 1
            throw TestFailure(description: "the client went away")
        }
        #expect(writes == 1)
        #expect(log.events == [.failed("a connection closed: the client went away")])
    }
}
