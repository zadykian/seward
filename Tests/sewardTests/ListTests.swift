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
}
