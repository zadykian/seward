import Foundation

/// `seward list`: a line for each key file of seward's in the keys' directory, `NAME TYPE
/// FINGERPRINT STORE` with a tab between. A file that does not load has the store `error`, and `-`
/// for the rest.
enum List {
    /// Runs the call. `arguments` leaves out `list`.
    static func run(_ arguments: [String], context: Context) -> Outcome {
        guard arguments.isEmpty else {
            return Outcome(status: .usage, errors: "seward: list takes no argument\n" + Cli.usage)
        }
        do {
            var outcome = Outcome(status: .success)
            for name in try context.keys.keyNames() {
                let path = context.keys.keyPath(name)
                do {
                    guard let contents = try KeyDirectory.regularFileContents(path), KeyFile.isSeward(contents)
                    else { continue }
                    outcome.output += try row(name, contents, enclave: context.enclave)
                } catch let error as SystemError where error.code == ENOENT {
                    continue  // The file vanished since the directory was read.
                } catch {
                    // The line keeps its place in the list, and its reason goes to the errors.
                    outcome.output += "\(name)\t-\t-\terror\n"
                    let reason = error is SystemError ? "\(error)" : "\(path): \(error)"
                    outcome.errors += "seward: \(reason)\n"
                    outcome.status = .failure
                }
            }
            return outcome
        } catch {
            return Outcome(status: .failure, errors: "seward: \(error)\n")
        }
    }

    /// The line of the key whose file holds `contents`.
    private static func row(_ name: KeyName, _ contents: Data, enclave: any Enclave) throws -> String {
        let file = try KeyFile.decode(contents)
        let key: SigningKey
        do {
            key = try SigningKey.load(file, enclave: enclave)
        } catch {
            throw KeyLoadError(reason: "its key does not load on this Mac: \(error)")
        }
        let fingerprint = SSHPublicKey(key.publicKey).fingerprint
        return "\(name)\t\(SSHPublicKey.type)\t\(fingerprint)\t\(file.store.rawValue)\n"
    }
}

/// Why the store of a key's file does not give the key.
private struct KeyLoadError: Error, CustomStringConvertible {
    let reason: String

    var description: String { reason }
}

extension KeyDirectory {
    /// The names in the directory that a key may take, sorted, whatever the files are: a missing
    /// directory holds none. A dot file, such as a write's temporary one, is no name.
    func keyNames() throws -> [KeyName] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: path)
            .compactMap(KeyName.init).sorted { $0.value < $1.value }
    }
}
