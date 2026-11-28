import CryptoKit
import Foundation

/// A key's private half, of either store, as CryptoKit holds it.
enum SigningKey {
    case enclave(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    /// Loads the key of a file from the store that it names: an enclave's through `enclave`, which
    /// a test gives of its own.
    static func load(_ file: KeyFile, enclave: any Enclave) throws -> SigningKey {
        switch file.store {
        case .enclave:
            return try enclave.loadKey(file.key)
        case .file:
            let key = try P256.Signing.PrivateKey(rawRepresentation: file.key)
            return .software(key)
        }
    }

    var publicKey: P256.Signing.PublicKey {
        switch self {
        case .enclave(let key): key.publicKey
        case .software(let key): key.publicKey
        }
    }

    /// What the key's file holds: the enclave's wrapped key, or the software key whole.
    var representation: Data {
        switch self {
        case .enclave(let key): key.dataRepresentation
        case .software(let key): key.rawRepresentation
        }
    }

    /// Signs the SHA-256 of `data`, which CryptoKit takes itself, as `ecdsa-sha2-nistp256` asks.
    func signature(for data: Data) throws -> P256.Signing.ECDSASignature {
        switch self {
        case .enclave(let key):
            return try key.signature(for: data)
        case .software(let key):
            return try key.signature(for: data)
        }
    }
}

extension SSHPublicKey {
    init(_ key: P256.Signing.PublicKey) {
        self.init(point: key.x963Representation)
    }

    /// The fingerprint as `ssh-keygen -l` prints it: the blob's SHA-256 in base64, with no padding.
    var fingerprint: String {
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }
}
