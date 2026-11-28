import Foundation
import Testing

@testable import seward

/// A client's side of a connection: its bytes, given in reads of `chunk` bytes at most.
final class ClientBytes {
    private var rest: Data
    private let chunk: Int
    /// How many bytes the reads asked for in all, to show what the agent never reads.
    private(set) var asked = 0

    init(_ bytes: Data, chunk: Int = .max) {
        rest = bytes
        self.chunk = chunk
    }

    func read(_ count: Int) -> Data {
        asked += count
        let taken = rest.prefix(min(count, chunk))
        rest = rest.dropFirst(taken.count)
        return Data(taken)
    }
}

@Suite struct AgentWireTests {
    @Test func aMessageReadsWholeAcrossReadsOfOneByte() throws {
        let client = ClientBytes(Data([0, 0, 0, 3, 13, 1, 2, 0, 0, 0, 1, 11]), chunk: 1)
        #expect(try AgentWire.nextMessage(client.read) == Data([13, 1, 2]))
        #expect(try AgentWire.nextMessage(client.read) == Data([11]))
        #expect(try AgentWire.nextMessage(client.read) == nil)
    }

    @Test(arguments: [
        [0],
        [0, 0, 0],
        [0, 0, 0, 5, 11],
        [0, 0, 1, 0] + [UInt8](repeating: 11, count: 255),
    ] as [[UInt8]])
    func aMessageThatEndsBeforeItsLengthIsCutShort(bytes: [UInt8]) {
        #expect(throws: AgentWireError.cutShort) { try AgentWire.nextMessage(ClientBytes(Data(bytes)).read) }
    }

    @Test(arguments: [AgentWire.maximumLength + 1, UInt32.max])
    func aMessageOverTheLimitIsReadNoFurtherThanItsLength(length: UInt32) {
        let client = ClientBytes(AgentWire.uint32(length) + Data(repeating: 11, count: 1024))
        #expect(throws: AgentWireError.tooLong(length)) { try AgentWire.nextMessage(client.read) }
        #expect(client.asked == 4)
    }

    @Test func aMessageOfTheLimitIsRead() throws {
        let message = Data([13]) + Data(repeating: 0, count: Int(AgentWire.maximumLength) - 1)
        let client = ClientBytes(AgentWire.framed(message), chunk: 4096)
        #expect(try AgentWire.nextMessage(client.read) == message)
    }

    @Test func aFramedMessageHasItsLengthBeforeIt() {
        #expect(AgentWire.framed(Data([5])) == Data([0, 0, 0, 1, 5]))
        #expect(AgentWire.string(Data(repeating: 7, count: 258)).prefix(4) == Data([0, 0, 1, 2]))
    }
}
