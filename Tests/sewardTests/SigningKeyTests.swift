import CryptoKit
import Foundation
import Testing

@testable import seward

@Suite struct SigningKeyTests {
    private let message = Data("a message to sign".utf8)

    @Test func aKeyOfTheFileStoreLoadsWholeFromItsFile() throws {
        let key = P256.Signing.PrivateKey()
        let enclave = RecordingEnclave()
        let loaded = try SigningKey.load(KeyFile(store: .file, key: key.rawRepresentation), enclave: enclave)
        #expect(loaded.publicKey.x963Representation == key.publicKey.x963Representation)
        #expect(loaded.representation == key.rawRepresentation)
        #expect(enclave.loads == 0)
    }

    @Test func aKeyOfTheEnclaveStoreLoadsThroughTheEnclave() throws {
        let key = P256.Signing.PrivateKey()
        let enclave = RecordingEnclave()
        let loaded = try SigningKey.load(KeyFile(store: .enclave, key: key.rawRepresentation), enclave: enclave)
        #expect(loaded.publicKey.x963Representation == key.publicKey.x963Representation)
        #expect(enclave.loads == 1)
    }

    @Test func aSignatureVerifiesWithThePublicKey() throws {
        let key = SigningKey.software(P256.Signing.PrivateKey())
        let signature = try key.signature(for: message)
        #expect(key.publicKey.isValidSignature(signature, for: message))
    }

    @Test(.enabled(if: SecureEnclave.isAvailable, "this Mac has no Secure Enclave"))
    func theSecureEnclaveMakesAKeyThatLoadsFromItsFileAndSigns() throws {
        let chip = SecureEnclaveChip()
        let key = try chip.makeKey(.keygen)
        let signature = try chip.loadKey(key.representation).signature(for: message)
        #expect(key.publicKey.isValidSignature(signature, for: message))
    }
}
