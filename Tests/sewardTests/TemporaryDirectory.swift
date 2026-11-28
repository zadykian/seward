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

/// The permission bits of what is at `path`, or nil where nothing is.
func permissions(of path: String) -> mode_t? {
    var info = stat()
    return lstat(path, &info) == 0 ? info.st_mode & 0o7777 : nil
}

/// The names in the directory at `path`, sorted.
func names(in path: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: path).sorted()
}
