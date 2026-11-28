import Foundation

/// The ssh-agent protocol's messages, as the agent reads and writes them on a connection. A
/// message is its length in four bytes, big endian, then its type in one byte and its contents.
enum AgentWire {
    /// The longest message that the agent reads, as OpenSSH's own agent bounds it.
    static let maximumLength: UInt32 = 256 * 1024

    static let failure: UInt8 = 5
    static let requestIdentities: UInt8 = 11
    static let identitiesAnswer: UInt8 = 12
    static let signRequest: UInt8 = 13
    static let signResponse: UInt8 = 14

    /// The next message of a connection, its type and contents with no length, or nil where the
    /// connection ends between two messages. `input` gives up to the count's bytes, none at the end.
    static func nextMessage(_ input: (Int) throws -> Data) throws -> Data? {
        let header = try bytes(4, of: input)
        if header.isEmpty { return nil }
        guard header.count == 4 else { throw AgentWireError.cutShort }
        let length = header.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        // Checked before a byte of it is read, so that a client cannot make the agent hold more.
        guard length <= maximumLength else { throw AgentWireError.tooLong(length) }
        let message = try bytes(Int(length), of: input)
        guard message.count == length else { throw AgentWireError.cutShort }
        return message
    }

    /// The message with its length before it, as the connection carries it.
    static func framed(_ message: Data) -> Data {
        uint32(UInt32(message.count)) + message
    }

    /// `count` bytes of `input`, or fewer where it ends first.
    private static func bytes(_ count: Int, of input: (Int) throws -> Data) throws -> Data {
        var bytes = Data()
        while bytes.count < count {
            let chunk = try input(count - bytes.count)
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        return bytes
    }

    /// ssh's `uint32`: four bytes, big endian.
    static func uint32(_ value: UInt32) -> Data {
        Data([24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
    }

    /// ssh's `string`: its length as a `uint32`, then its bytes.
    static func string(_ bytes: Data) -> Data {
        uint32(UInt32(bytes.count)) + bytes
    }
}

/// Why the agent closes a connection: the client broke the protocol's frame.
enum AgentWireError: Error, Equatable, CustomStringConvertible {
    /// A message's length is over `AgentWire.maximumLength`.
    case tooLong(UInt32)
    /// A message has no type, or a field of it ends past the message.
    case cutShort

    var description: String {
        switch self {
        case .tooLong(let length): "a message of \(length) bytes is over the \(AgentWire.maximumLength) the agent reads"
        case .cutShort: "a message has no type, or a field ends past the message"
        }
    }
}
