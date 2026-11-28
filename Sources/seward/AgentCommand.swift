import Foundation

/// `seward agent`: serves the keys to ssh on `~/.ssh/seward.sock` until it is stopped. A failure
/// of the lock or the socket goes to the agent's log, and the call exits 1.
enum AgentCommand {
    /// Runs the call. `arguments` leaves out `agent`.
    static func run(_ arguments: [String], context: Context) -> Outcome {
        guard arguments.isEmpty else {
            return Outcome(status: .usage, errors: "seward: agent takes no argument\n" + Cli.usage)
        }
        // A client that closes before its answer fails that write alone, rather than ending the
        // agent, as OpenSSH's agent does.
        signal(SIGPIPE, SIG_IGN)
        let log = SystemLog()
        do {
            try serve(AgentSocket(in: context.keys), keys: context.keys, log: log)
        } catch {
            log.record(.failed("\(error)"))
            return Outcome(status: .failure)
        }
    }

    /// Accepts each connection and serves it on a thread of its own, so that a client that holds
    /// one open keeps no other waiting.
    private static func serve(_ socket: AgentSocket, keys: KeyDirectory, log: SystemLog) throws -> Never {
        // The shortage that the agent waits out, which the log names once as it begins.
        var shortage: Int32?
        while true {
            let connection = accept(socket.descriptor, nil, nil)
            guard connection >= 0 else {
                let error = SystemError(path: socket.path, code: errno)
                switch error.code {
                case EINTR, ECONNABORTED:
                    continue
                // Out of descriptors or memory for now: a moment later, a closed connection may
                // have given some back.
                case EMFILE, ENFILE, ENOBUFS, ENOMEM:
                    if shortage != error.code { log.record(.failed("\(error)")) }
                    shortage = error.code
                    usleep(100_000)
                    continue
                default:
                    throw error
                }
            }
            shortage = nil
            let path = socket.path
            Thread.detachNewThread {
                answer(connection, keys: keys, path: path)
            }
        }
    }

    /// Serves one connection, with an agent of its own, as an Agent is not Sendable, then closes it.
    private static func answer(_ connection: Int32, keys: KeyDirectory, path: String) {
        defer { close(connection) }
        let agent = Agent(context: Context(keys: keys, enclave: SecureEnclaveChip()), log: SystemLog())
        agent.serve(
            input: { count in try receive(upTo: count, from: connection, path: path) },
            output: { data in try send(data, to: connection, path: path) })
    }

    /// Up to `count` bytes of the connection, as one read gives them, and none at its end.
    static func receive(upTo count: Int, from connection: Int32, path: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: min(count, 65_536))
        while true {
            let received = read(connection, &buffer, buffer.count)
            if received < 0 && errno == EINTR { continue }
            guard received >= 0 else { throw SystemError(path: path, code: errno) }
            return Data(buffer[0..<received])
        }
    }

    /// Writes all of `data` to the connection. A client that closed it fails the write with EPIPE.
    static func send(_ data: Data, to connection: Int32, path: String) throws {
        var rest = data[...]
        while !rest.isEmpty {
            let sent = rest.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
            if sent < 0 && errno == EINTR { continue }
            guard sent >= 0 else { throw SystemError(path: path, code: errno) }
            rest = rest.dropFirst(sent)
        }
    }
}
