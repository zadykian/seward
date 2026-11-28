import Foundation

/// A key as the agent serves it: its name, which ssh shows as its comment, the blob of its public
/// key, which a sign request names, and its signing.
struct AgentKey {
    var name: String
    var blob: Data
    /// Signs the data, and returns r and s, 32 bytes each, as CryptoKit's `rawRepresentation`.
    var sign: (Data) throws -> Data
}

/// The agent's answers, each a message's type and contents.
enum AgentAnswer {
    static let failure = Data([AgentWire.failure])

    /// The keys' count, then each key's blob and name.
    static func identities(_ keys: [AgentKey]) -> Data {
        var answer = Data([AgentWire.identitiesAnswer]) + AgentWire.uint32(UInt32(keys.count))
        for key in keys {
            answer += AgentWire.string(key.blob) + AgentWire.string(Data(key.name.utf8))
        }
        return answer
    }

    /// An `ecdsa-sha2-nistp256` signature as RFC 5656 gives it: its type, then r and s as two
    /// mpints. `raw` is r, then s of the same length.
    static func signature(_ raw: Data) -> Data {
        let half = raw.count / 2
        let numbers = mpint(raw.prefix(half)) + mpint(raw.suffix(half))
        let blob = AgentWire.string(Data(SSHPublicKey.type.utf8)) + AgentWire.string(numbers)
        return Data([AgentWire.signResponse]) + AgentWire.string(blob)
    }

    /// A number of `magnitude`'s bytes, big endian, as ssh's `mpint`: with no zero byte before
    /// it, but for one before a first bit that is set, which would read as a negative number.
    static func mpint(_ magnitude: Data) -> Data {
        var bytes = Data(magnitude.drop { $0 == 0 })
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return AgentWire.string(bytes)
    }
}
