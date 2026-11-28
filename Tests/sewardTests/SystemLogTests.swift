import Foundation
import OSLog
import Testing

@testable import seward

@Suite struct SystemLogTests {
    @Test func theUnifiedLogHoldsEachLineUnderSewardAtItsLevel() throws {
        let name = "work-\(UUID().uuidString)"
        let start = Date().addingTimeInterval(-1)
        SystemLog().record(.signed(name: name))
        SystemLog().record(.skipped(path: "/keys/\(name)", reason: "it is damaged"))
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == SystemLog.subsystem && $0.composedMessage.contains(name) }
        let lines = ["signed with the key \(name)", "skipped /keys/\(name): it is damaged"]
        #expect(entries.map(\.composedMessage) == lines)
        #expect(entries.map(\.level) == [.notice, .error])
    }
}
