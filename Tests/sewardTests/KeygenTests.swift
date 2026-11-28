import CryptoKit
import Foundation
import Security
import Testing

@testable import seward

@Suite struct KeygenTests {
    /// Runs `seward keygen` on the keys' directory `ROOT/.ssh`.
    private func keygen(
        _ arguments: [String], in root: String, enclave: RecordingEnclave = RecordingEnclave()
    ) -> Outcome {
        let context = Context(keys: KeyDirectory(path: root + "/.ssh"), enclave: enclave)
        return Cli.run(["keygen"] + arguments, context: context)
    }

    /// The key that `keygen --store file work` made, as CryptoKit reads it.
    private func softwareKey(in root: String) throws -> P256.Signing.PrivateKey {
        let file = try KeyFile.decode(Data(contentsOf: URL(fileURLWithPath: root + "/.ssh/work")))
        return try P256.Signing.PrivateKey(rawRepresentation: file.key)
    }

    /// What `program` prints on its standard output.
    private func output(of program: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let printed = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        return String(bytes: printed, encoding: .utf8) ?? ""
    }

    @Test(arguments: Store.allCases)
    func aNewPairHasItsModesAndKeygenPrintsItsPublicKey(store: Store) throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            let outcome = keygen(["--store", store.rawValue, "work"], in: root)
            #expect(outcome.status == .success)
            #expect(outcome.errors.isEmpty)
            #expect(try names(in: keys) == ["work", "work.pub"])
            #expect(permissions(of: keys) == 0o700)
            #expect(permissions(of: keys + "/work") == 0o600)
            #expect(permissions(of: keys + "/work.pub") == 0o644)
            #expect(try String(contentsOfFile: keys + "/work.pub", encoding: .utf8) == outcome.output)
            #expect(try KeyFile.decode(Data(contentsOf: URL(fileURLWithPath: keys + "/work"))).store == store)
        }
    }

    @Test func thePublicKeyIsTheKeysPublicHalf() throws {
        try withTemporaryDirectory { root throws in
            let outcome = keygen(["--store", "file", "work"], in: root)
            let point = try softwareKey(in: root).publicKey.x963Representation
            let fields = outcome.output.split(separator: " ")
            try #require(fields.count == 3)
            #expect(fields[0] == "ecdsa-sha2-nistp256")
            #expect(fields[2] == "work\n")
            let blob = try #require(Data(base64Encoded: String(fields[1])))
            #expect(blob.suffix(point.count) == point)
        }
    }

    @Test func sshKeygenReadsThePublicKeyAndItsFingerprint() throws {
        try withTemporaryDirectory { root throws in
            _ = keygen(["--store", "file", "work"], in: root)
            let fingerprint = SSHPublicKey(try softwareKey(in: root).publicKey).fingerprint
            let printed = try output(of: "/usr/bin/ssh-keygen", ["-l", "-f", root + "/.ssh/work.pub"])
            #expect(printed == "256 \(fingerprint) work (ECDSA)\n")
        }
    }

    @Test func keygenAsksTheEnclaveForAKeyAfterFirstUnlockOnThisMacAlone() throws {
        try withTemporaryDirectory { root throws in
            let enclave = RecordingEnclave()
            _ = keygen(["work"], in: root, enclave: enclave)
            let access = KeyAccess(
                protection: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, flags: .privateKeyUsage)
            #expect(enclave.accesses == [access])
        }
    }

    @Test func theFileStoreAsksNothingOfTheEnclave() throws {
        try withTemporaryDirectory { root throws in
            let enclave = RecordingEnclave(isAvailable: false)
            #expect(keygen(["--store", "file", "work"], in: root, enclave: enclave).status == .success)
            #expect(enclave.accesses.isEmpty)
        }
    }

    @Test func aMacWithNoSecureEnclaveGetsNoKeyOfItsStore() throws {
        try withTemporaryDirectory { root throws in
            let enclave = RecordingEnclave(isAvailable: false)
            let outcome = keygen(["work"], in: root, enclave: enclave)
            #expect(outcome == Outcome(status: .failure, errors: "seward: \(KeygenError.noSecureEnclave)\n"))
            #expect(try names(in: root).isEmpty)
            #expect(enclave.accesses.isEmpty)
        }
    }

    @Test(.disabled(if: SecureEnclave.isAvailable, "this Mac has a Secure Enclave"))
    func thisMacWithNoSecureEnclaveGetsNoKeyOfItsStore() throws {
        try withTemporaryDirectory { root throws in
            let context = Context(keys: KeyDirectory(path: root + "/.ssh"), enclave: SecureEnclaveChip())
            let outcome = Cli.run(["keygen", "work"], context: context)
            #expect(outcome == Outcome(status: .failure, errors: "seward: \(KeygenError.noSecureEnclave)\n"))
            #expect(try names(in: root).isEmpty)
        }
    }

    @Test(arguments: Store.allCases)
    func aKeyAloneGetsItsPublicKeyFromItsOwnStore(store: Store) throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            let first = keygen(["--store", store.rawValue, "work"], in: root)
            let key = try Data(contentsOf: URL(fileURLWithPath: keys + "/work"))
            #expect(unlink(keys + "/work.pub") == 0)
            let enclave = RecordingEnclave()
            let other: Store = store == .enclave ? .file : .enclave
            #expect(keygen(["--store", other.rawValue, "work"], in: root, enclave: enclave) == first)
            #expect(try Data(contentsOf: URL(fileURLWithPath: keys + "/work")) == key)
            #expect(permissions(of: keys + "/work.pub") == 0o644)
            #expect(enclave.accesses.isEmpty)
            #expect(enclave.loads == (store == .enclave ? 1 : 0))
        }
    }

    @Test func aPairInPlaceStaysAndKeygenSaysToRemoveIt() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            _ = keygen(["work"], in: root)
            let before = try files(in: keys)
            let outcome = keygen(["work"], in: root)
            let errors = "seward: \(keys)/work and its .pub exist: `seward remove work` deletes them\n"
            #expect(outcome == Outcome(status: .failure, errors: errors))
            #expect(try files(in: keys) == before)
        }
    }

    @Test func aPublicKeyAloneStaysAndKeygenSaysToRemoveIt() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            #expect(mkdir(keys, 0o700) == 0)
            try write("ecdsa-sha2-nistp256 AAAA work\n", to: keys + "/work.pub")
            let before = try files(in: keys)
            let outcome = keygen(["work"], in: root)
            let errors = "seward: \(keys)/work.pub exists with no key: `seward remove work` deletes it\n"
            #expect(outcome == Outcome(status: .failure, errors: errors))
            #expect(try files(in: keys) == before)
        }
    }

    @Test(arguments: [false, true])
    func aFileNotOfSewardsStays(withAPublicKey: Bool) throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            #expect(mkdir(keys, 0o700) == 0)
            try write("not a key of seward's\n", to: keys + "/work")
            if withAPublicKey {
                try write("ecdsa-sha2-nistp256 AAAA work\n", to: keys + "/work.pub")
            }
            let before = try files(in: keys)
            let outcome = keygen(["work"], in: root)
            #expect(outcome == Outcome(status: .failure, errors: "seward: \(KeygenError.notSeward(keys + "/work"))\n"))
            #expect(try files(in: keys) == before)
        }
    }

    @Test func aKeygenRemovesWhatOneCutShortLeftAndARefusedOneDoesNot() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            let leftover = keys + "/" + KeyDirectory.temporaryPrefix + UUID().uuidString
            #expect(mkdir(keys, 0o700) == 0)
            try write("seward-key 1 file\nAAAA\n", to: leftover)
            try write("not seward's\n", to: keys + "/home")
            #expect(backdate(leftover, by: 120))
            #expect(keygen(["home"], in: root).status == .failure)
            #expect(KeyDirectory.exists(leftover))
            #expect(keygen(["--store", "file", "work"], in: root).status == .success)
            #expect(try names(in: keys) == ["home", "work", "work.pub"])
        }
    }

    @Test func aDirectoryOfTheNameIsNotSewards() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            #expect(mkdir(keys, 0o700) == 0)
            #expect(mkdir(keys + "/work", 0o700) == 0)
            let outcome = keygen(["work"], in: root)
            #expect(outcome == Outcome(status: .failure, errors: "seward: \(KeygenError.notSeward(keys + "/work"))\n"))
            #expect(try names(in: keys) == ["work"])
        }
    }

    @Test(arguments: [
        ("seward-key 2 enclave\nAAAA\n", "its version, 2, is newer than this seward reads: update seward"),
        ("seward-key 1 enclave\n", "the key's file is damaged: its second line is no key in base64"),
        ("seward-key 1 file\nAAAA\n", "its key does not load on this Mac: "),
        ("seward-key 1 enclave\nAAAA\n", "its key does not load on this Mac: "),
    ] as [(String, String)])
    func aKeyThatDoesNotReadStaysWithNoPublicKey(text: String, reason: String) throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            #expect(mkdir(keys, 0o700) == 0)
            try write(text, to: keys + "/work")
            let outcome = keygen(["work"], in: root)
            #expect(outcome.status == .failure)
            #expect(outcome.errors.hasPrefix("seward: \(keys)/work: \(reason)"))
            #expect(try names(in: keys) == ["work"])
        }
    }

    @Test(arguments: [[], ["work.pub"], ["--store", "tpm", "work"], ["work", "home"]] as [[String]])
    func aWrongCallExitsTwoAndWritesNothing(arguments: [String]) throws {
        try withTemporaryDirectory { root throws in
            let outcome = keygen(arguments, in: root)
            #expect(outcome.status == .usage)
            #expect(outcome.errors.hasSuffix(Cli.usage))
            #expect(try names(in: root).isEmpty)
        }
    }
}
