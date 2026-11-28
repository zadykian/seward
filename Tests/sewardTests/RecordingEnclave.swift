import CryptoKit
import Foundation

@testable import seward

/// A Secure Enclave of the test's own: it notes what keygen asks of it and gives software keys,
/// which any Mac and any runner make. A lock guards the notes, which the compiler cannot see, as
/// the agent may call it from a thread per connection.
final class RecordingEnclave: Enclave, @unchecked Sendable {
    let isAvailable: Bool
    private let lock = NSLock()
    private var notedAccesses: [KeyAccess] = []
    private var notedLoads = 0

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    var accesses: [KeyAccess] { lock.withLock { notedAccesses } }
    var loads: Int { lock.withLock { notedLoads } }

    func makeKey(_ access: KeyAccess) throws -> SigningKey {
        lock.withLock { notedAccesses.append(access) }
        return .software(P256.Signing.PrivateKey())
    }

    func loadKey(_ representation: Data) throws -> SigningKey {
        lock.withLock { notedLoads += 1 }
        return .software(try P256.Signing.PrivateKey(rawRepresentation: representation))
    }
}
