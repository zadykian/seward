import Foundation

@testable import seward

/// A home of a test's own, under `/tmp`, where the test runs the built seward and OpenSSH's tools.
/// Each program gets no environment but the home's, as the test's own holds the runner's.
struct TestHome {
    let path: String

    var socket: String { path + "/.ssh/seward.sock" }

    /// The seward that the package built, beside the tests' bundle, where SwiftPM puts both.
    static var seward: String {
        let bundle = Bundle(for: BundleMarker.self).bundleURL
        let directory = bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent() : bundle
        return directory.appending(component: "seward").path(percentEncoded: false)
    }

    /// Starts `program`, which prints to files of the home, and reads `input`'s file where it is
    /// given.
    func start(
        _ program: String, _ arguments: [String], environment: [String: String] = [:], input: String? = nil
    ) throws -> Started {
        let name = "\(path)/\(URL(fileURLWithPath: program).lastPathComponent)-\(UUID().uuidString.prefix(8))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.environment = ["HOME": path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"].merging(environment) { $1 }
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardInput = try input.map { try Self.handle(reading: $0) } ?? FileHandle.nullDevice
        process.standardOutput = try Self.handle(writing: name + ".out")
        process.standardError = try Self.handle(writing: name + ".err")
        // A test's thread blocks signals, and a program started from it would too: sshd would miss
        // SIGCHLD. The program starts with none blocked.
        var none = sigset_t()
        var blocked = sigset_t()
        sigemptyset(&none)
        pthread_sigmask(SIG_SETMASK, &none, &blocked)
        defer { pthread_sigmask(SIG_SETMASK, &blocked, nil) }
        try process.run()
        return Started(process: process, outputPath: name + ".out", errorsPath: name + ".err")
    }

    /// Runs `program` to its end. One that runs past 30 seconds is stopped, and fails the test.
    func run(
        _ program: String, _ arguments: [String], environment: [String: String] = [:], input: String? = nil
    ) throws -> Finished {
        let started = try start(program, arguments, environment: environment, input: input)
        guard eventually(within: 30, { !started.process.isRunning }) else {
            started.stop()
            throw TestFailure(description: "\(program) ran past 30 seconds: \(started.errors)")
        }
        started.process.waitUntilExit()
        return Finished(status: started.process.terminationStatus, output: started.output, errors: started.errors)
    }

    private static func handle(reading path: String) throws -> FileHandle {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw TestFailure(description: "no \(path)") }
        return handle
    }

    private static func handle(writing path: String) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: path, contents: nil),
            let handle = FileHandle(forWritingAtPath: path)
        else { throw TestFailure(description: "\(path) was not made") }
        return handle
    }
}

/// A class of the tests' bundle, by which Foundation finds the bundle.
private final class BundleMarker {}

/// A program that a test started, with the files that take what it prints.
struct Started {
    let process: Process
    let outputPath: String
    let errorsPath: String

    var output: String { (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? "" }
    var errors: String { (try? String(contentsOfFile: errorsPath, encoding: .utf8)) ?? "" }

    /// Stops the program by SIGKILL, which it cannot block or handle, so that it stops for sure.
    func stop() {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        _ = eventually(within: 10) { !process.isRunning }
    }
}

/// A program's run to its end: its status and what it printed.
struct Finished {
    let status: Int32
    let output: String
    let errors: String
}

/// Whether `condition` holds within `seconds`, checked each 20 milliseconds.
func eventually(within seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: seconds)
    while !condition() {
        guard Date() < deadline else { return false }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return true
}

/// Whether a connection to the Unix socket at `path` is accepted.
func connects(to path: String) -> Bool {
    guard let address = SocketAddress(path) else { return false }
    let client = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(client) }
    return address.withPointer { connect(client, $0, $1) } == 0
}

/// A connection to the agent's socket that a test speaks the protocol on, as ssh does. It closes
/// as the test lets it go, and a read waits 10 seconds at most, so that a silent agent fails it.
final class AgentClient {
    private let descriptor: Int32

    init(_ path: String) throws {
        guard let address = SocketAddress(path) else { throw TestFailure(description: "no socket's address: \(path)") }
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        guard address.withPointer({ connect(client, $0, $1) }) == 0 else {
            let reason = String(cString: strerror(errno))
            close(client)
            throw TestFailure(description: "\(path) did not connect: \(reason)")
        }
        descriptor = client
    }

    deinit { close(descriptor) }

    func send(_ data: Data) throws {
        try AgentCommand.send(data, to: descriptor, path: "the test's client")
    }

    /// The agent's next message, or nil where the agent closed the connection.
    func receive() throws -> Data? {
        try AgentWire.nextMessage { count in
            try AgentCommand.receive(upTo: count, from: descriptor, path: "the test's client")
        }
    }
}
