import Foundation
import Testing

@testable import seward

/// The built `seward agent` as OpenSSH's own tools reach it. Each test makes a software key,
/// `work`, in a home of its own, so that it runs on a Mac with no Secure Enclave, and stops what
/// it started on every path out.
@Suite(.serialized) struct AgentProgramTests {
    @Test func sshAddListsTheKeys() throws {
        try withAgent { home, _ in
            let listed = try home.run("/usr/bin/ssh-add", ["-L"], environment: ["SSH_AUTH_SOCK": home.socket])
            let publicKey = try String(contentsOfFile: home.path + "/.ssh/work.pub", encoding: .utf8)
            #expect(listed.status == 0, "\(listed.errors)")
            #expect(listed.output == publicKey)
        }
    }

    @Test func sshKeygenSignsThroughTheAgentAndItsSignatureVerifies() throws {
        try withAgent { home, _ in
            let data = home.path + "/data"
            try write("signed through seward\n", to: data)
            let signed = try home.run(
                "/usr/bin/ssh-keygen", ["-Y", "sign", "-n", "file", "-f", home.path + "/.ssh/work.pub", data],
                environment: ["SSH_AUTH_SOCK": home.socket])
            #expect(signed.status == 0, "\(signed.errors)")
            let publicKey = try String(contentsOfFile: home.path + "/.ssh/work.pub", encoding: .utf8)
            try write("seward-test " + publicKey, to: home.path + "/allowed_signers")
            let verify = ["-Y", "verify", "-f", home.path + "/allowed_signers", "-I", "seward-test", "-n", "file"]
            let verified = try home.run("/usr/bin/ssh-keygen", verify + ["-s", data + ".sig"], input: data)
            #expect(verified.status == 0, "\(verified.errors)")
        }
    }

    /// Runs `body` with a home that holds the key `work` and an agent that serves it, which it
    /// stops after.
    private func withAgent(_ body: (TestHome, Started) throws -> Void) throws {
        try withShortDirectory { path in
            let home = TestHome(path: path)
            let keygen = try home.run(TestHome.seward, ["keygen", "--store", "file", "work"])
            try #require(keygen.status == 0, "\(keygen.errors)")
            let agent = try home.start(TestHome.seward, ["agent"])
            defer { agent.stop() }
            let socket = home.socket
            try #require(
                eventually(within: 10) { connects(to: socket) }, "the agent did not serve: \(agent.errors)")
            try body(home, agent)
        }
    }
}
