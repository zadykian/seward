import Foundation

/// The keys of seward's files in the keys' directory, as the agent reads them at each request.
enum AgentKeyFiles {
    /// The largest key's file that the agent reads. A key's file is under a kilobyte, and a file
    /// of the keys' directory may be anything.
    static let maximumSize = 64 * 1024

    /// The keys of seward's files in `directory`, by name, each as `load` makes it. A file that is
    /// not seward's is passed over. One of seward's that does not read or load is skipped, and the
    /// log says why, so that the rest still reach ssh.
    static func keys(
        in directory: KeyDirectory, log: any AgentLog, load: (KeyName, KeyFile) throws -> AgentKey
    ) -> [AgentKey] {
        guard KeyDirectory.exists(directory.path) else { return [] }
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            log.record(.failed("the keys' directory \(directory.path) does not list: \(error.localizedDescription)"))
            return []
        }
        var keys: [AgentKey] = []
        for name in entries.sorted().compactMap(KeyName.init) {
            let path = directory.keyPath(name)
            let file: KeyFile
            do {
                guard let contents = try contentsIfSeward(path) else { continue }
                file = try KeyFile.decode(contents)
            } catch {
                log.record(.skipped(path: path, reason: "\(error)"))
                continue
            }
            do {
                keys.append(try load(name, file))
            } catch {
                log.record(.skipped(path: path, reason: "its key does not load on this Mac: \(error)"))
            }
        }
        return keys
    }

    /// The contents of the file at `path` where it is seward's, or nil for any other file, or for
    /// a link, a directory or a pipe. It reads through one descriptor, which follows no link and
    /// waits on no pipe, so that a file swapped after the check never blocks the agent.
    private static func contentsIfSeward(_ path: String) throws -> Data? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw AgentKeyFileError.unopened(errno)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { return nil }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            // Gone, or a link now, since the check.
            if errno == ENOENT || errno == ELOOP { return nil }
            throw AgentKeyFileError.unopened(errno)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        defer { try? handle.close() }
        guard fstat(descriptor, &info) == 0 else { throw AgentKeyFileError.unopened(errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { return nil }
        let contents = try handle.read(upToCount: maximumSize + 1) ?? Data()
        guard KeyFile.isSeward(contents) else { return nil }
        guard contents.count <= maximumSize else { throw AgentKeyFileError.tooLarge }
        return contents
    }
}

/// Why a key's file does not read, for the log's line of its path.
enum AgentKeyFileError: Error, Equatable, CustomStringConvertible {
    case unopened(Int32)
    case tooLarge

    var description: String {
        switch self {
        case .unopened(let code): "it does not open: \(String(cString: strerror(code)))"
        case .tooLarge: "it is over the \(AgentKeyFiles.maximumSize) bytes that the agent reads of a key's file"
        }
    }
}
