import Foundation
import Testing

@testable import seward

/// What a load refuses: the key `refused`.
private struct LoadRefused: Error, CustomStringConvertible {
    var description: String { "the enclave refused" }
}

@Suite struct AgentKeyFilesTests {
    private let log = RecordingLog()

    /// The keys' names in `ROOT/.ssh`, each loaded as its file's key bytes, but for `refused`.
    private func names(_ root: String) -> [String] {
        AgentKeyFiles.keys(in: KeyDirectory(path: root + "/.ssh"), log: log) { name, file in
            guard file.key != Data("refused".utf8) else { throw LoadRefused() }
            return AgentKey(name: name.value, blob: file.key) { _ in Data() }
        }.map(\.name)
    }

    /// Writes a key's file of `store` that holds `key`, in `ROOT/.ssh`, and returns its path.
    @discardableResult
    private func keyFile(_ name: String, in root: String, key: String = "key", store: Store = .file) throws -> String {
        try KeyDirectory(path: root + "/.ssh").create()
        let path = root + "/.ssh/" + name
        try KeyFile(store: store, key: Data(key.utf8)).encoded().write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test func aMissingDirectoryHoldsNoKey() throws {
        try withTemporaryDirectory { root throws in
            #expect(names(root).isEmpty)
            #expect(log.events.isEmpty)
        }
    }

    @Test func theKeysOfEachStoreAreListedByName() throws {
        try withTemporaryDirectory { root throws in
            try keyFile("work", in: root, store: .enclave)
            try keyFile("home", in: root, store: .file)
            try keyFile("Laptop-2.old", in: root)
            #expect(names(root) == ["Laptop-2.old", "home", "work"])
            #expect(log.events.isEmpty)
        }
    }

    @Test func filesNotOfSewardsAndNamesOffTheRuleArePassedOver() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            try keyFile("work", in: root)
            try write("Host *\n", to: keys + "/config")
            try write("-----BEGIN OPENSSH PRIVATE KEY-----\n", to: keys + "/id_ed25519")
            try write("", to: keys + "/empty")
            try write("seward-keys 1 file\na2V5\n", to: keys + "/near")
            for name in [".hidden", "work.pub", "agent.sock", "a b", "-dash"] {
                try keyFile(name, in: root)
            }
            #expect(names(root) == ["work"])
            #expect(log.events.isEmpty)
        }
    }

    @Test func aLinkAPipeAndADirectoryArePassedOverAndNeverRead() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            let target = try keyFile("work", in: root)
            #expect(symlink(target, keys + "/link") == 0)
            #expect(symlink(keys + "/nowhere", keys + "/broken") == 0)
            #expect(mkfifo(keys + "/pipe", 0o600) == 0)
            #expect(mkdir(keys + "/directory", 0o700) == 0)
            #expect(names(root) == ["work"])
            #expect(log.events.isEmpty)
        }
    }

    @Test func aKeyThatDoesNotReadIsSkippedAndLoggedAndTheRestListed() throws {
        try withTemporaryDirectory { root throws in
            let keys = root + "/.ssh"
            try keyFile("a-work", in: root)
            try write("seward-key 2 file\nnew form\n", to: keys + "/b-newer")
            try write("seward-key 1 file\n!\n", to: keys + "/c-damaged")
            let refused = try keyFile("d-refused", in: root, key: "refused")
            try keyFile("e-home", in: root)
            #expect(names(root) == ["a-work", "e-home"])
            #expect(
                log.events == [
                    .skipped(path: keys + "/b-newer", reason: "\(KeyFileError.newer(version: "2"))"),
                    .skipped(
                        path: keys + "/c-damaged",
                        reason: "\(KeyFileError.damaged("its second line is no key in base64"))"),
                    .skipped(
                        path: refused, reason: "its key does not load on this Mac: the enclave refused"),
                ])
        }
    }

    @Test func aKeysFileOverTheBoundIsSkippedAndLoggedButNotOneAtIt() throws {
        try withTemporaryDirectory { root throws in
            let path = try keyFile("big", in: root)
            // No key's file is this long, so one at the bound reads and is damaged, and one past it
            // does not read.
            let header = "seward-key 1 file\n"
            try write(header + String(repeating: "k", count: AgentKeyFiles.maximumSize - header.count), to: path)
            _ = names(root)
            try write(header + String(repeating: "k", count: AgentKeyFiles.maximumSize - header.count + 1), to: path)
            #expect(names(root).isEmpty)
            #expect(
                log.events == [
                    .skipped(path: path, reason: "\(KeyFileError.damaged("its second line is no key in base64"))"),
                    .skipped(path: path, reason: "\(AgentKeyFileError.tooLarge)"),
                ])
        }
    }

    @Test(.enabled(if: geteuid() != 0, "root opens a file of any mode"))
    func aFileThatDoesNotOpenIsSkippedAndLogged() throws {
        try withTemporaryDirectory { root throws in
            let path = try keyFile("work", in: root)
            #expect(chmod(path, 0) == 0)
            #expect(names(root).isEmpty)
            #expect(log.events == [.skipped(path: path, reason: "\(AgentKeyFileError.unopened(EACCES))")])
        }
    }

    @Test func aKeysDirectoryThatDoesNotListIsLogged() throws {
        try withTemporaryDirectory { root throws in
            try write("", to: root + "/.ssh")
            #expect(names(root).isEmpty)
            guard case .failed(let reason) = try #require(log.events.first) else {
                Issue.record("not a failure: \(log.events)")
                return
            }
            #expect(reason.hasPrefix("the keys' directory \(root)/.ssh does not list: "))
        }
    }
}
