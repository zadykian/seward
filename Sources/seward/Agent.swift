import Foundation

/// What the agent logs: each signature, each key's file that it skips, and each failure.
enum AgentEvent: Equatable, CustomStringConvertible {
    case signed(name: String)
    case skipped(path: String, reason: String)
    case failed(String)

    var description: String {
        switch self {
        case .signed(let name): "signed with the key \(name)"
        case let .skipped(path, reason): "skipped \(path): \(reason)"
        case .failed(let reason): reason
        }
    }
}

/// Where the agent's lines go: the system's log, or a test's record of them.
protocol AgentLog {
    func record(_ event: AgentEvent)
}

/// The agent's answers to ssh's requests, by the ssh-agent protocol: it lists the keys, signs with
/// one, and refuses every other request.
struct Agent {
    /// The keys as they are at a request: read again at each, so that a new key needs no restart.
    let keys: () -> [AgentKey]
    let log: any AgentLog

    /// The answer to a message, its type and contents. Throws where it is cut short, as the
    /// connection then closes.
    func answer(_ message: Data) throws -> Data {
        switch try AgentRequest(message) {
        case .identities:
            return AgentAnswer.identities(keys())
        case .sign(key: let blob, data: let data, flags: _):
            guard let key = keys().first(where: { $0.blob == blob }) else { return AgentAnswer.failure }
            return sign(data, with: key)
        case .other:
            return AgentAnswer.failure
        }
    }

    private func sign(_ data: Data, with key: AgentKey) -> Data {
        do {
            let answer = AgentAnswer.signature(try key.sign(data))
            log.record(.signed(name: key.name))
            return answer
        } catch {
            log.record(.failed("the key \(key.name) did not sign: \(error)"))
            return AgentAnswer.failure
        }
    }

    /// Answers a connection's messages in turn, until the client ends it. A message that breaks
    /// the frame, or a failure to read or write, ends it too, and the log says why. The caller
    /// then closes the connection. `input` gives up to the count's bytes, none at the end.
    func serve(input: (Int) throws -> Data, output: (Data) throws -> Void) {
        do {
            while let message = try AgentWire.nextMessage(input) {
                try output(AgentWire.framed(answer(message)))
            }
        } catch {
            log.record(.failed("a connection closed: \(error)"))
        }
    }
}
