import Foundation
import Testing

@testable import seward

@Suite struct KeyDirectoryTests {
    @Test func aMissingDirectoryIsMadeWithModeSevenHundred() throws {
        try withTemporaryDirectory { root throws in
            let keys = KeyDirectory(path: root + "/.ssh")
            try keys.create()
            #expect(permissions(of: keys.path) == 0o700)
            try keys.create()
            #expect(permissions(of: keys.path) == 0o700)
        }
    }

    @Test func aDirectoryInPlaceKeepsItsMode() throws {
        try withTemporaryDirectory { root throws in
            #expect(chmod(root, 0o755) == 0)
            try KeyDirectory(path: root).create()
            #expect(permissions(of: root) == 0o755)
        }
    }

    @Test(arguments: [0o600, 0o644] as [mode_t])
    func aNewFileHoldsItsContentsWithItsModeAndNothingElseIsLeft(mode: mode_t) throws {
        try withTemporaryDirectory { root throws in
            let keys = KeyDirectory(path: root)
            try keys.writeNew(Data("contents\n".utf8), to: root + "/work", mode: mode)
            #expect(try String(contentsOfFile: root + "/work", encoding: .utf8) == "contents\n")
            #expect(permissions(of: root + "/work") == mode)
            #expect(try names(in: root) == ["work"])
        }
    }

    @Test func aFileInPlaceStaysAndNothingElseIsLeft() throws {
        try withTemporaryDirectory { root throws in
            let keys = KeyDirectory(path: root)
            try Data("before\n".utf8).write(to: URL(fileURLWithPath: root + "/work"))
            #expect(throws: SystemError(path: root + "/work", code: EEXIST)) {
                try keys.writeNew(Data("after\n".utf8), to: root + "/work", mode: 0o600)
            }
            #expect(try String(contentsOfFile: root + "/work", encoding: .utf8) == "before\n")
            #expect(try names(in: root) == ["work"])
        }
    }

    @Test func aLinkThatLeadsNowhereExistsAndStays() throws {
        try withTemporaryDirectory { root throws in
            #expect(symlink(root + "/nowhere", root + "/work") == 0)
            #expect(KeyDirectory.exists(root + "/work"))
            #expect(!KeyDirectory.exists(root + "/nowhere"))
            #expect(throws: SystemError(path: root + "/work", code: EEXIST)) {
                try KeyDirectory(path: root).writeNew(Data(), to: root + "/work", mode: 0o600)
            }
            #expect(!KeyDirectory.exists(root + "/nowhere"))
        }
    }

    @Test func aFileOfSewardsIsReadAndAnythingElseIsNot() throws {
        try withTemporaryDirectory { root throws in
            let contents = Data("seward-key 1 file\nAAAA\n".utf8)
            try contents.write(to: URL(fileURLWithPath: root + "/work"))
            #expect(try KeyDirectory.sewardFileContents(root + "/work") == contents)
            #expect(try KeyDirectory.sewardFileContents(root + "/work", upTo: 12) == contents.prefix(12))
            try write("-----BEGIN OPENSSH PRIVATE KEY-----\n", to: root + "/home")
            #expect(try KeyDirectory.sewardFileContents(root + "/home") == nil)
            #expect(mkdir(root + "/folder", 0o700) == 0)
            #expect(try KeyDirectory.sewardFileContents(root + "/folder") == nil)
            #expect(symlink(root + "/work", root + "/link") == 0 && symlink(root + "/none", root + "/broken") == 0)
            #expect(try KeyDirectory.sewardFileContents(root + "/link") == nil)
            #expect(try KeyDirectory.sewardFileContents(root + "/broken") == nil)
            #expect(throws: SystemError(path: root + "/none", code: ENOENT)) {
                try KeyDirectory.sewardFileContents(root + "/none")
            }
        }
    }

    @Test func anotherToolsFileIsReadNoFurtherThanTheTagsBytes() throws {
        let other = Data("-----BEGIN OPENSSH PRIVATE KEY-----\n".utf8)
        let seward = Data("seward-key 1 file\nAAAA\n".utf8)
        for (contents, expected) in [(other, nil), (seward, seward)] as [(Data, Data?)] {
            var ends: [Int32] = [0, 0]
            #expect(pipe(&ends) == 0)
            defer { close(ends[0]) }
            #expect(write(ends[1], [UInt8](contents), contents.count) == contents.count)
            close(ends[1])
            #expect(try KeyDirectory.sewardContents(of: ends[0], path: "pipe", upTo: .max) == expected)
            // A pipe gives what is left: the bytes past the tag's stay unread in it.
            let left = try FileHandle(fileDescriptor: ends[0], closeOnDealloc: false).readToEnd() ?? Data()
            #expect(left == (expected == nil ? contents.dropFirst(KeyFile.tag.utf8.count + 1) : Data()))
        }
    }

    @Test(.enabled(if: geteuid() != 0, "root reads every file"))
    func aFileThatCannotBeReadThrowsItsReason() throws {
        try withTemporaryDirectory { root throws in
            try Data("contents\n".utf8).write(to: URL(fileURLWithPath: root + "/work"))
            #expect(chmod(root + "/work", 0) == 0)
            #expect(throws: SystemError(path: root + "/work", code: EACCES)) {
                try KeyDirectory.sewardFileContents(root + "/work")
            }
        }
    }
}
