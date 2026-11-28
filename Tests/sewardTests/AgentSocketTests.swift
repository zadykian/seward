import Foundation
import Testing

@testable import seward

@Suite(.serialized) struct AgentSocketTests {
    @Test func itMakesTheDirectoryAndBindsTheSocket0600() throws {
        try withShortDirectory { home in
            let keys = KeyDirectory(path: home + "/.ssh")
            let socket = try AgentSocket(in: keys)
            defer { socket.release() }
            #expect(socket.path == keys.path + "/seward.sock")
            #expect(permissions(of: keys.path) == 0o700)
            #expect(permissions(of: socket.path) == 0o600)
            #expect(permissions(of: keys.path + "/seward.lock") == 0o600)
        }
    }

    @Test func aSecondAgentFindsTheLockHeld() throws {
        try withShortDirectory { home in
            let keys = KeyDirectory(path: home)
            let first = try AgentSocket(in: keys)
            defer { first.release() }
            #expect(throws: AgentSocketError.locked(home + "/seward.lock")) { try AgentSocket(in: keys) }
        }
    }

    @Test func anAgentReplacesTheSocketThatNobodyAnswersOn() throws {
        try withShortDirectory { home in
            let keys = KeyDirectory(path: home)
            try AgentSocket(in: keys).release()
            #expect(KeyDirectory.exists(home + "/seward.sock"))
            let socket = try AgentSocket(in: keys)
            defer { socket.release() }
            #expect(permissions(of: socket.path) == 0o600)
        }
    }

    @Test func aSocketThatAnswersStaysAndStopsTheAgent() throws {
        try withShortDirectory { home in
            // Another agent on the path, with no lock of seward's, as OpenSSH's own.
            let other = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { close(other) }
            let address = try #require(SocketAddress(home + "/seward.sock"))
            #expect(address.withPointer { bind(other, $0, $1) } == 0)
            #expect(listen(other, 1) == 0)
            #expect(throws: AgentSocketError.answered(home + "/seward.sock")) {
                try AgentSocket(in: KeyDirectory(path: home))
            }
            #expect(KeyDirectory.exists(home + "/seward.sock"))
        }
    }

    @Test func aFileAtTheSocketsPathStaysAndStopsTheAgent() throws {
        try withShortDirectory { home in
            try write("no socket", to: home + "/seward.sock")
            #expect(throws: AgentSocketError.notSocket(home + "/seward.sock")) {
                try AgentSocket(in: KeyDirectory(path: home))
            }
            #expect(try files(in: home)["seward.sock"] == Data("no socket".utf8))
            // The lock went with the failure, so that a next start finds it free.
            try FileManager.default.removeItem(atPath: home + "/seward.sock")
            try AgentSocket(in: KeyDirectory(path: home)).release()
        }
    }

    @Test func aPathPastASocketsAddressStopsTheAgent() throws {
        try withShortDirectory { home in
            let keys = KeyDirectory(path: home + "/" + String(repeating: "k", count: 100))
            #expect(throws: AgentSocketError.tooLong(keys.path + "/seward.sock")) { try AgentSocket(in: keys) }
        }
    }

    @Test func anAddressHoldsUpTo103Bytes() {
        #expect(SocketAddress(String(repeating: "a", count: 103)) != nil)
        #expect(SocketAddress(String(repeating: "a", count: 104)) == nil)
    }
}
