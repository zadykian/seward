import CryptoKit
import Foundation
import Security

/// The protection and the flags that keygen passes to the Secure Enclave. A test reads them
/// here, as a `SecAccessControl` cannot be read back.
struct KeyAccess: Equatable {
    /// Usable from the Mac's first unlock after its start, on this Mac alone, with no Touch ID and
    /// no password: a tunnel and an unattended commit sign with nobody there.
    static var keygen: KeyAccess {
        KeyAccess(protection: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, flags: .privateKeyUsage)
    }

    var protection: String
    var flags: SecAccessControlCreateFlags
}

/// The Secure Enclave, behind a protocol, so that a test sees what keygen asks of it and gets a
/// software key in its place.
protocol Enclave {
    var isAvailable: Bool { get }
    func makeKey(_ access: KeyAccess) throws -> SigningKey
    func loadKey(_ representation: Data) throws -> SigningKey
}

/// This Mac's Secure Enclave, through CryptoKit. Its keys are no keychain items, which would ask
/// for a password when another program, or seward rebuilt, reads one.
struct SecureEnclaveChip: Enclave {
    var isAvailable: Bool { SecureEnclave.isAvailable }

    func makeKey(_ access: KeyAccess) throws -> SigningKey {
        var error: Unmanaged<CFError>?
        guard
            let control = SecAccessControlCreateWithFlags(
                nil, access.protection as CFString, access.flags, &error)
        else {
            throw AccessControlError(reason: error.map { "\($0.takeRetainedValue())" } ?? "no reason given")
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: control)
        return .enclave(key)
    }

    func loadKey(_ representation: Data) throws -> SigningKey {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: representation)
        return .enclave(key)
    }
}

/// Why the Secure Enclave's access control for a new key could not be made.
struct AccessControlError: Error, CustomStringConvertible {
    let reason: String

    var description: String { "the Secure Enclave's access control: \(reason)" }
}
