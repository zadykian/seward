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

    @Test func anSshdOfTheTestsOwnTakesALoginThroughTheAgent() throws {
        try withAgent { home, _ in
            let port = try freePort()
            let sshd = try startSshd(in: home, port: port)
            defer { sshd.stop() }
            let login = try home.run(
                "/usr/bin/ssh",
                [
                    "-F", "/dev/null", "-p", "\(port)", "-l", NSUserName(),
                    "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=\(home.socket)",
                    "-o", "IdentityFile=\(home.path)/.ssh/work.pub",
                    "-o", "UserKnownHostsFile=\(home.path)/known_hosts", "-o", "GlobalKnownHostsFile=/dev/null",
                    "-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                    "127.0.0.1", "echo", "logged-in",
                ])
            #expect(login.status == 0, "\(login.errors)\nsshd: \(sshd.errors)")
            #expect(login.output == "logged-in\n")
        }
    }

    @Test func aClientThatClosesBeforeItsAnswerLeavesTheAgentServing() throws {
        try withAgent { home, agent in
            let address = try #require(SocketAddress(home.socket))
            let client = socket(AF_UNIX, SOCK_STREAM, 0)
            // Were the agent gone, a write would fail rather than end the tests.
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            let connected = address.withPointer { connect(client, $0, $1) } == 0
            // A thousand requests fit in the socket's buffer, and their answers overfill the
            // client's: the agent is still writing them when the client closes. macOS's shutdown
            // leaves the agent's writes going, so the client closes the socket.
            let request = AgentWire.framed(Data([AgentWire.requestIdentities]))
            let requests = Data(repeatElement(request, count: 1000).joined())
            let written = connected ? requests.withUnsafeBytes { write(client, $0.baseAddress, $0.count) } : -1
            close(client)
            try #require(connected)
            #expect(written == requests.count)
            #expect(eventually(within: 10) { agent.errors.contains("seward: a connection closed: ") })
            #expect(agent.process.isRunning)
            let listed = try home.run("/usr/bin/ssh-add", ["-L"], environment: ["SSH_AUTH_SOCK": home.socket])
            #expect(listed.status == 0, "\(listed.errors)")
        }
    }

    @Test func aConnectionThatBreaksTheFrameClosesAloneWhileAnotherIsServed() throws {
        try withAgent { home, agent in
            let request = AgentWire.framed(Data([AgentWire.requestIdentities]))
            let broken = try AgentClient(home.socket)
            let served = try AgentClient(home.socket)
            // Half a length holds the first connection's thread waiting while the second is served.
            try broken.send(Data([0xff, 0xff]))
            try served.send(request)
            #expect(try served.receive()?.first == AgentWire.identitiesAnswer)
            // The length's other half puts it over the bound, and the agent closes that connection.
            try broken.send(Data([0xff, 0xff]))
            #expect(try broken.receive() == nil)
            let closed = "seward: a connection closed: \(AgentWireError.tooLong(UInt32.max))\n"
            #expect(eventually(within: 10) { agent.errors.contains(closed) })
            try served.send(request)
            #expect(try served.receive()?.first == AgentWire.identitiesAnswer)
        }
    }

    @Test func aSecondStartFindsTheLockAndExitsOne() throws {
        try withAgent { home, agent in
            let second = try home.run(TestHome.seward, ["agent"])
            #expect(second.status == 1)
            #expect(second.errors.contains("seward: \(home.path)/.ssh/seward.lock: another agent holds the lock\n"))
            #expect(agent.process.isRunning)
            #expect(connects(to: home.socket))
        }
    }

    /// A port of 127.0.0.1 that nobody listens on, as the system picks for a socket bound to 0.
    private func freePort() throws -> UInt16 {
        let probe = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(probe) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(probe, $0, length) == 0 && getsockname(probe, $0, &length) == 0
            }
        }
        guard bound else { throw TestFailure(description: "no free port: \(String(cString: strerror(errno)))") }
        return UInt16(bigEndian: address.sin_port)
    }

    /// Starts an sshd of the home's own on `port`, which takes the key `work` for this user, and
    /// waits for it to listen. It runs as this user, who alone may log in to it.
    private func startSshd(in home: TestHome, port: UInt16) throws -> Started {
        let hostKey = try home.run(
            "/usr/bin/ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", home.path + "/host_key"])
        try #require(hostKey.status == 0, "\(hostKey.errors)")
        let authorized = home.path + "/authorized_keys"
        try FileManager.default.copyItem(atPath: home.path + "/.ssh/work.pub", toPath: authorized)
        let config = """
            Port \(port)
            ListenAddress 127.0.0.1
            HostKey \(home.path)/host_key
            PidFile \(home.path)/sshd.pid
            AuthorizedKeysFile \(authorized)
            UsePAM no
            PermitUserRC no
            StrictModes no
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            LogLevel VERBOSE

            """
        try write(config, to: home.path + "/sshd_config")
        let sshd = try home.start("/usr/sbin/sshd", ["-D", "-e", "-f", home.path + "/sshd_config"])
        guard eventually(within: 10, { sshd.errors.contains("Server listening") }) else {
            sshd.stop()
            throw TestFailure(description: "sshd did not listen: \(sshd.errors)")
        }
        return sshd
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
