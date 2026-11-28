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

    /// The contents of the regular file at `path` where it is seward's, up to `limit` bytes, or nil
    /// for anything else: a link, a directory or a pipe, which seward never follows or reads, or
    /// another tool's file, of which it reads no further than the tag.
    static func sewardFileContents(_ path: String, upTo limit: Int = .max) throws -> Data? {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw SystemError(path: path, code: errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { return nil }
        // Opened by the descriptor, so that a link or a pipe swapped in since lstat is not followed or
        // waited on, and every failure is the system's, with its errno.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw SystemError(path: path, code: errno) }
        defer { close(descriptor) }
        guard fstat(descriptor, &info) == 0 else { throw SystemError(path: path, code: errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { return nil }
        return try sewardContents(of: descriptor, path: path, upTo: limit)
    }

    /// What is left of `descriptor`, up to `limit` bytes, where it starts with seward's tag, or nil
    /// with nothing read past the tag's bytes: another tool's key never enters memory whole.
    static func sewardContents(of descriptor: Int32, path: String, upTo limit: Int) throws -> Data? {
        let head = try bytes(of: descriptor, path: path, upTo: min(limit, KeyFile.tag.utf8.count + 1))
        guard KeyFile.isSeward(head) else { return nil }
        return head + (try bytes(of: descriptor, path: path, upTo: limit - head.count))
    }

    /// Up to `limit` bytes of `descriptor`, fewer at its end.
    private static func bytes(of descriptor: Int32, path: String, upTo limit: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < limit {
            let count = read(descriptor, &buffer, min(buffer.count, limit - data.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw SystemError(path: path, code: errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
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

    /// The start of a file's name that `writeNew` writes before it links it: no key's name starts so.
    static let temporaryPrefix = ".seward-"

    /// Removes the files that a write cut short left: `.seward-UUID`, a regular file of this user's,
    /// past `age` seconds old, as a write in progress is younger. One that does not go stays.
    func removeLeftovers(olderThan age: TimeInterval = 60) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
        for name in names where name.hasPrefix(Self.temporaryPrefix) {
            guard UUID(uuidString: String(name.dropFirst(Self.temporaryPrefix.count))) != nil,
                let attributes = try? FileManager.default.attributesOfItem(atPath: "\(path)/\(name)"),
                attributes[.type] as? FileAttributeType == .typeRegular,
                (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
                let modified = attributes[.modificationDate] as? Date,
                -modified.timeIntervalSinceNow > age
            else { continue }
            unlink("\(path)/\(name)")
        }
    }

    /// Writes a new file at `target`, whole or not at all, and never over a file there. It writes
    /// a file of a name that no key takes, then links it as `target`, which fails where one exists.
    func writeNew(_ contents: Data, to target: String, mode: mode_t) throws {
        let temporary = "\(path)/\(Self.temporaryPrefix)\(UUID().uuidString)"
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
