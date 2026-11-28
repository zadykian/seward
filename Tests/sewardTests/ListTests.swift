import CryptoKit
import Foundation
import Testing

@testable import seward

@Suite struct ListTests {
    /// Runs `seward ARGUMENTS` on the keys' directory `ROOT/.ssh`.
    private func seward(
        _ arguments: [String], in root: String, enclave: RecordingEnclave = RecordingEnclave()
    ) -> Outcome {
        Cli.run(arguments, context: Context(keys: KeyDirectory(path: root + "/.ssh"), enclave: enclave))
    }

    /// The fingerprint of the key that `keygen` made as `name`.
    private func fingerprint(of name: String, in root: String) throws -> String {
        let file = try KeyFile.decode(Data(contentsOf: URL(fileURLWithPath: root + "/.ssh/" + name)))
        return SSHPublicKey(try P256.Signing.PrivateKey(rawRepresentation: file.key).publicKey).fingerprint
    }

    @Test func aLineForEachKeyHoldsItsNameTypeFingerprintAndStore() throws {
        try withTemporaryDirectory { root throws in
            let enclave = RecordingEnclave()
            _ = seward(["keygen", "--store", "file", "zed"], in: root)
            _ = seward(["keygen", "alpha"], in: root, enclave: enclave)
            let outcome = seward(["list"], in: root, enclave: enclave)
            let type = "ecdsa-sha2-nistp256"
            let expected =
                "alpha\t\(type)\t\(try fingerprint(of: "alpha", in: root))\tenclave\n"
                + "zed\t\(type)\t\(try fingerprint(of: "zed", in: root))\tfile\n"
            #expect(outcome == Outcome(status: .success, output: expected))
            #expect(enclave.loads == 1)
        }
    }

    @Test func listSkipsEveryFileThatIsNoKeyOfSewards() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            let made = seward(["keygen", "--store", "file", "work"], in: root)
            let contents = try String(contentsOfFile: keys + "/work", encoding: .utf8)
            try write("Host *\n  ServerAliveInterval 30\n", to: keys + "/config")
            try write("-----BEGIN OPENSSH PRIVATE KEY-----\n", to: keys + "/id_ed25519")
            try write("", to: keys + "/empty")
            try write(contents, to: keys + "/seward.sock")
            try write(contents, to: keys + "/.seward-0000")
            try FileManager.default.createDirectory(atPath: keys + "/folder", withIntermediateDirectories: false)
            #expect(symlink(keys + "/work", keys + "/linked") == 0)
            let outcome = seward(["list"], in: root)
            let expected = "work\tecdsa-sha2-nistp256\t\(try fingerprint(of: "work", in: root))\tfile\n"
            #expect(made.status == .success)
            #expect(outcome == Outcome(status: .success, output: expected))
        }
    }

    @Test func aFileThatDoesNotLoadHasTheStoreErrorAndListExitsOneAfterTheRest() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            _ = seward(["keygen", "--store", "file", "good"], in: root)
            let short = Data([1, 2, 3]).base64EncodedString()
            try write("seward-key 1 enclave\n\(short)\n", to: keys + "/another-mac")
            try write("seward-key 1 file\n\(short)\n", to: keys + "/short")
            try write("seward-key 1 file\nnot base64!\n", to: keys + "/damaged")
            try write("seward-key 2 file\n\(short)\n", to: keys + "/newer")
            let outcome = seward(["list"], in: root)
            let good = "good\tecdsa-sha2-nistp256\t\(try fingerprint(of: "good", in: root))\tfile\n"
            let expected =
                "another-mac\t-\t-\terror\ndamaged\t-\t-\terror\n" + good + "newer\t-\t-\terror\nshort\t-\t-\terror\n"
            #expect(outcome.status == .failure)
            #expect(outcome.output == expected)
            let reasons = outcome.errors.split(separator: "\n").map(String.init)
            try #require(reasons.count == 4)
            #expect(reasons[0].hasPrefix("seward: \(keys)/another-mac: its key does not load on this Mac: "))
            #expect(reasons[1].hasPrefix("seward: \(keys)/damaged: the key's file is damaged: "))
            #expect(reasons[2].hasPrefix("seward: \(keys)/newer: its version, 2, is newer"))
            #expect(reasons[3].hasPrefix("seward: \(keys)/short: its key does not load on this Mac: "))
        }
    }

    @Test(.enabled(if: geteuid() != 0, "root reads every file"))
    func aFileThatCannotBeReadHasTheStoreErrorAndListExitsOne() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            _ = seward(["keygen", "--store", "file", "locked"], in: root)
            #expect(chmod(keys + "/locked", 0) == 0)
            let outcome = seward(["list"], in: root)
            let output = "locked\t-\t-\terror\n"
            let errors = "seward: \(keys)/locked: Permission denied\n"
            #expect(outcome == Outcome(status: .failure, output: output, errors: errors))
        }
    }

    @Test func aMissingDirectoryAndAnEmptyOneListNothing() throws {
        try withTemporaryDirectory { root throws in
            #expect(seward(["list"], in: root) == Outcome(status: .success))
            try FileManager.default.createDirectory(atPath: root + "/.ssh", withIntermediateDirectories: false)
            #expect(seward(["list"], in: root) == Outcome(status: .success))
        }
    }

    @Test func listTakesNoArgument() throws {
        try withTemporaryDirectory { root throws in
            let outcome = seward(["list", "work"], in: root)
            #expect(outcome == Outcome(status: .usage, errors: "seward: list takes no argument\n" + Cli.usage))
        }
    }
}
