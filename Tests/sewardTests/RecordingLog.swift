@testable import seward

/// The agent's log, kept for the test to read.
final class RecordingLog: AgentLog {
    private(set) var events: [AgentEvent] = []

    func record(_ event: AgentEvent) {
        events.append(event)
    }
}
