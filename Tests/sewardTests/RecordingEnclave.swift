import CryptoKit
import Foundation

@testable import seward

/// A Secure Enclave of the test's own: it notes what keygen asks of it and gives software keys,
/// which any Mac and any runner make.
final class RecordingEnclave: Enclave {
    let isAvailable: Bool
    private(set) var accesses: [KeyAccess] = []
    private(set) var loads = 0

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func makeKey(_ access: KeyAccess) throws -> SigningKey {
        accesses.append(access)
        return .software(P256.Signing.PrivateKey())
    }

    func loadKey(_ representation: Data) throws -> SigningKey {
        loads += 1
        return .software(try P256.Signing.PrivateKey(rawRepresentation: representation))
    }
}
