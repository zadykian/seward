import Foundation

/// `seward list`: a line for each key file of seward's in the keys' directory.
enum List {
    /// Runs the call. `arguments` leaves out `list`.
    static func run(_ arguments: [String], context: Context) -> Outcome {
        guard arguments.isEmpty else {
            return Outcome(status: .usage, errors: "seward: list takes no argument\n" + Cli.usage)
        }
        do {
            var output = ""
            for name in try context.keys.keyNames() {
                let path = context.keys.keyPath(name)
                guard let contents = try? KeyDirectory.regularFileContents(path), KeyFile.isSeward(contents)
                else { continue }
                let file = try KeyFile.decode(contents)
                let key = try SigningKey.load(file, enclave: context.enclave)
                let fingerprint = SSHPublicKey(key.publicKey).fingerprint
                output += "\(name)\t\(SSHPublicKey.type)\t\(fingerprint)\t\(file.store.rawValue)\n"
            }
            return Outcome(status: .success, output: output)
        } catch {
            return Outcome(status: .failure, errors: "seward: \(error)\n")
        }
    }
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
