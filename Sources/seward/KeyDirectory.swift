import Foundation

/// The keys' directory, `~/.ssh`, as a value, so that a test gives a directory of its own.
struct KeyDirectory {
    let path: String

    /// The key's file, which holds its private half.
    func keyPath(_ name: KeyName) -> String { "\(path)/\(name.value)" }

    /// The key's public half, as ssh reads it.
    func publicKeyPath(_ name: KeyName) -> String { "\(path)/\(name.value).pub" }

    /// Whether anything is at `path`, a link that leads nowhere included.
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// The contents of the regular file at `path`, or nil for anything else, as a link, a directory
    /// or a pipe, which seward never follows or reads.
    static func regularFileContents(_ path: String) throws -> Data? {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw SystemError(path: path, code: errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Makes the directory, 0700, where it is missing, and leaves one that exists as it is.
    func create() throws {
        if mkdir(path, 0o700) == 0 {
            // The umask may have taken bits off the mode.
            guard chmod(path, 0o700) == 0 else { throw SystemError(path: path, code: errno) }
        } else if errno != EEXIST {
            throw SystemError(path: path, code: errno)
        }
    }

    /// Writes a new file at `target`, whole or not at all, and never over a file there. It writes
    /// a file of a name that no key takes, then links it as `target`, which fails where one exists.
    func writeNew(_ contents: Data, to target: String, mode: mode_t) throws {
        let temporary = "\(path)/.seward-\(UUID().uuidString)"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SystemError(path: temporary, code: errno) }
        defer { unlink(temporary) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        defer { try? handle.close() }
        try handle.write(contentsOf: contents)
        guard fchmod(descriptor, mode) == 0 else { throw SystemError(path: temporary, code: errno) }
        try handle.synchronize()
        guard link(temporary, target) == 0 else { throw SystemError(path: target, code: errno) }
    }
}

/// A call of the system that failed, with the path it was for and its reason.
struct SystemError: Error, Equatable, CustomStringConvertible {
    let path: String
    let code: Int32

    var description: String { "\(path): \(String(cString: strerror(code)))" }
}
