import Foundation

/// The agent's listening socket, `seward.sock` in the keys' directory, and the lock it holds while
/// it serves, `seward.lock` there. The lock comes first, so that two agents never race for the
/// socket.
struct AgentSocket {
    let descriptor: Int32
    let lockDescriptor: Int32
    let path: String

    /// Takes the lock, then binds the socket: it replaces a socket that nobody answers on, and
    /// refuses one that an agent answers on and anything that is no socket. It makes a missing
    /// keys' directory, 0700, as keygen does.
    init(in keys: KeyDirectory) throws {
        try keys.create()
        let lockPath = keys.path + "/seward.lock"
        let lock = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw SystemError(path: lockPath, code: errno) }
        do {
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                if errno == EWOULDBLOCK { throw AgentSocketError.locked(lockPath) }
                throw SystemError(path: lockPath, code: errno)
            }
            path = keys.path + "/seward.sock"
            descriptor = try Self.listening(at: path)
            lockDescriptor = lock
        } catch {
            close(lock)
            throw error
        }
    }

    /// Closes the socket and the lock. The socket's file stays, for the next agent to replace.
    func release() {
        close(descriptor)
        close(lockDescriptor)
    }

    private static func listening(at path: String) throws -> Int32 {
        guard let address = SocketAddress(path) else { throw AgentSocketError.tooLong(path) }
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK else { throw AgentSocketError.notSocket(path) }
            guard try !answers(address, path: path) else { throw AgentSocketError.answered(path) }
            guard unlink(path) == 0 || errno == ENOENT else { throw SystemError(path: path, code: errno) }
        } else if errno != ENOENT {
            throw SystemError(path: path, code: errno)
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SystemError(path: path, code: errno) }
        // Bound under 0177, as OpenSSH's agent binds its own: the socket is 0600 from its first
        // moment, and no other user ever connects.
        let mask = umask(0o177)
        let bound = address.withPointer { bind(descriptor, $0, $1) }
        let code = errno
        umask(mask)
        guard bound == 0 else {
            close(descriptor)
            throw SystemError(path: path, code: code)
        }
        guard listen(descriptor, SOMAXCONN) == 0 else {
            let code = errno
            close(descriptor)
            throw SystemError(path: path, code: code)
        }
        return descriptor
    }

    /// Whether an agent answers on the socket at `path`. A refused connection means that nobody
    /// listens on it, as after an agent that was killed.
    private static func answers(_ address: SocketAddress, path: String) throws -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw SystemError(path: path, code: errno) }
        defer { close(probe) }
        if address.withPointer({ connect(probe, $0, $1) }) == 0 { return true }
        guard errno == ECONNREFUSED || errno == ENOENT else { throw SystemError(path: path, code: errno) }
        return false
    }
}

/// A path as a Unix socket's address, which holds up to 103 bytes and a nul.
struct SocketAddress {
    private var address = sockaddr_un()

    init?(_ path: String) {
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    }

    /// Runs `call` with the address as bind and connect take it.
    func withPointer<Result>(_ call: (UnsafePointer<sockaddr>, socklen_t) -> Result) -> Result {
        withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                call($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

/// Why the agent does not serve: another agent, or a path that it leaves alone.
enum AgentSocketError: Error, Equatable, CustomStringConvertible {
    case locked(String)
    case answered(String)
    case notSocket(String)
    case tooLong(String)

    var description: String {
        switch self {
        case .locked(let path): "\(path): another agent holds the lock"
        case .answered(let path): "\(path): another agent answers on the socket"
        case .notSocket(let path): "\(path): not a socket, which the agent never removes"
        case .tooLong(let path): "\(path): longer than a socket's 103 bytes"
        }
    }
}
