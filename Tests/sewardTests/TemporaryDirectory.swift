import Foundation

/// Runs `body` with a new directory of the test's own, and removes it after, so that no test
/// touches the real `~/.ssh`.
func withTemporaryDirectory<Value>(_ body: (String) throws -> Value) throws -> Value {
    let path = FileManager.default.temporaryDirectory
        .appending(component: "seward-test-\(UUID().uuidString)").path(percentEncoded: false)
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(atPath: path) }
    return try body(path)
}

/// Runs `body` with a new directory under `/tmp`, and removes it after. A socket's path holds 103
/// bytes, and macOS's temporary directory for the user takes about half of them.
func withShortDirectory<Value>(_ body: (String) throws -> Value) throws -> Value {
    let path = "/tmp/seward-\(UUID().uuidString.prefix(8))"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(atPath: path) }
    return try body(path)
}

/// The permission bits of what is at `path`, or nil where nothing is.
func permissions(of path: String) -> mode_t? {
    var info = stat()
    return lstat(path, &info) == 0 ? info.st_mode & 0o7777 : nil
}

/// The names in the directory at `path`, sorted.
func names(in path: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: path).sorted()
}

/// The files of the directory at `path` by name, to show that a call changed none.
func files(in path: String) throws -> [String: Data] {
    var files: [String: Data] = [:]
    for name in try names(in: path) {
        files[name] = try Data(contentsOf: URL(fileURLWithPath: path + "/" + name))
    }
    return files
}

/// Writes `text` as a new file at `path`.
func write(_ text: String, to path: String) throws {
    try Data(text.utf8).write(to: URL(fileURLWithPath: path))
}
