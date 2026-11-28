import Foundation

/// `seward remove [--yes] NAME`: deletes whichever of the key's file and its `.pub` exist, once
/// the person types the name again.
enum Remove {
    /// Runs the call. `arguments` leaves out `remove`.
    static func run(_ arguments: [String], context: Context) -> Outcome {
        switch RemoveCall.parse(arguments) {
        case .failure(let wrong):
            return Outcome(status: .usage, errors: "seward: \(wrong.reason)\n" + Cli.usage)
        case .success(let call):
            guard call.confirmed else {
                return Outcome(status: .usage, errors: "seward: remove takes --yes\n" + Cli.usage)
            }
            do {
                return Outcome(status: .success, output: try remove(call, context: context))
            } catch {
                return Outcome(status: .failure, errors: "seward: \(error)\n")
            }
        }
    }

    /// Deletes the files and returns a line for each. A file that is not seward's is never deleted.
    private static func remove(_ call: RemoveCall, context: Context) throws -> String {
        let keyPath = context.keys.keyPath(call.name)
        let publicKeyPath = context.keys.publicKeyPath(call.name)
        let hasKey = KeyDirectory.exists(keyPath)
        let hasPublicKey = KeyDirectory.exists(publicKeyPath)
        guard hasKey || hasPublicKey else { throw RemoveError.missing(call.name) }
        if hasKey {
            guard let contents = try KeyDirectory.regularFileContents(keyPath), KeyFile.isSeward(contents)
            else { throw RemoveError.notSeward(keyPath) }
        }
        // The `.pub` goes first, so that a run cut short leaves the key alone, which keygen mends.
        let paths = (hasPublicKey ? [publicKeyPath] : []) + (hasKey ? [keyPath] : [])
        var output = ""
        for path in paths {
            guard unlink(path) == 0 || errno == ENOENT else { throw SystemError(path: path, code: errno) }
            output += "removed \(path)\n"
        }
        return output
    }
}

/// Why remove deleted nothing.
enum RemoveError: Error, Equatable, CustomStringConvertible {
    case missing(KeyName)
    case notSeward(String)
    case notConfirmed

    var description: String {
        switch self {
        case .missing(let name): "no key is named \(name): neither its file nor its .pub exists"
        case .notSeward(let path): "\(path) is not a key of seward's: it stays, and so does its .pub"
        case .notConfirmed: "the name was not typed again: nothing is deleted"
        }
    }
}
