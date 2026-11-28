import Foundation
import os

/// The agent's log: macOS's unified log, subsystem `seward`, and standard error, which a launchd
/// service's plist may name. Each line is marked public, as the unified log hides a string's value
/// by default.
struct SystemLog: AgentLog {
    static let subsystem = "seward"

    private let logger = Logger(subsystem: SystemLog.subsystem, category: "agent")

    func record(_ event: AgentEvent) {
        let line = event.description
        switch event {
        case .signed: logger.log("\(line, privacy: .public)")
        case .skipped, .failed: logger.error("\(line, privacy: .public)")
        }
        // A closed standard error loses the line, which the unified log still holds.
        try? FileHandle.standardError.write(contentsOf: Data("seward: \(line)\n".utf8))
    }
}
