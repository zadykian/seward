import CryptoKit
import Foundation

/// `seward keygen [--store enclave|file] NAME`: makes a key and its `.pub` in the keys'
/// directory, or writes the `.pub` of a key in place.
enum Keygen {
    /// Runs the call. `arguments` leaves out `keygen`.
    static func run(_ arguments: [String], context: Context) -> Outcome {
        switch KeygenCall.parse(arguments) {
        case .failure(let wrong):
            return Outcome(status: .usage, errors: "seward: \(wrong.reason)\n" + Cli.usage)
        case .success(let call):
            do {
                let line = try make(call, context: context)
                return Outcome(status: .success, output: line)
            } catch {
                return Outcome(status: .failure, errors: "seward: \(error)\n")
            }
        }
    }

    /// Writes what is missing of the pair, and returns the `.pub`'s line.
    private static func make(_ call: KeygenCall, context: Context) throws -> String {
        let keys = context.keys
        let keyPath = keys.keyPath(call.name)
        let publicKeyPath = keys.publicKeyPath(call.name)
        if KeyDirectory.exists(keyPath) {
            let key = try loadKeyInPlace(keyPath, name: call.name, context: context)
            return try writePublicKey(of: key, name: call.name, keys: keys)
        }
        if KeyDirectory.exists(publicKeyPath) {
            throw KeygenError.publicKeyAlone(publicKeyPath, call.name)
        }
        let key = try makeKey(call.store, enclave: context.enclave)
        try keys.create()
        let file = KeyFile(store: call.store, key: key.representation)
        try keys.writeNew(file.encoded(), to: keyPath, mode: 0o600)
        return try writePublicKey(of: key, name: call.name, keys: keys)
    }

    /// The key of a file in place whose `.pub` is missing. Its own store holds it, whatever
    /// `--store` says.
    private static func loadKeyInPlace(_ path: String, name: KeyName, context: Context) throws -> SigningKey {
        guard let contents = try KeyDirectory.sewardFileContents(path) else { throw KeygenError.notSeward(path) }
        if KeyDirectory.exists(context.keys.publicKeyPath(name)) {
            throw KeygenError.pairInPlace(path, name)
        }
        let file: KeyFile
        do {
            file = try KeyFile.decode(contents)
        } catch {
            throw KeygenError.unreadable(path, "\(error)")
        }
        do {
            return try SigningKey.load(file, enclave: context.enclave)
        } catch {
            throw KeygenError.unreadable(path, "its key does not load on this Mac: \(error)")
        }
    }

    private static func makeKey(_ store: Store, enclave: any Enclave) throws -> SigningKey {
        switch store {
        case .enclave:
            guard enclave.isAvailable else { throw KeygenError.noSecureEnclave }
            return try enclave.makeKey(.keygen)
        case .file:
            return .software(P256.Signing.PrivateKey())
        }
    }

    /// Writes the `.pub` last, so that a run cut short leaves the key alone, which a second run
    /// mends.
    private static func writePublicKey(of key: SigningKey, name: KeyName, keys: KeyDirectory) throws -> String {
        let line = SSHPublicKey(key.publicKey).line(comment: name.value)
        try keys.writeNew(Data(line.utf8), to: keys.publicKeyPath(name), mode: 0o644)
        return line
    }
}

/// Why keygen changed nothing.
enum KeygenError: Error, Equatable, CustomStringConvertible {
    case notSeward(String)
    case pairInPlace(String, KeyName)
    case publicKeyAlone(String, KeyName)
    case unreadable(String, String)
    case noSecureEnclave

    var description: String {
        switch self {
        case .notSeward(let path):
            "\(path) is not a key of seward's: move it, or take another name"
        case let .pairInPlace(path, name):
            "\(path) and its .pub exist: `seward remove \(name)` deletes them"
        case let .publicKeyAlone(path, name):
            "\(path) exists with no key: `seward remove \(name)` deletes it"
        case let .unreadable(path, reason):
            "\(path): \(reason)"
        case .noSecureEnclave:
            "the Secure Enclave is not available on this Mac: `--store file` keeps the key in its file"
        }
    }
}
