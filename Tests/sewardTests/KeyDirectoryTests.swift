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

    @Test func aRegularFileIsReadAndAnythingElseIsNot() throws {
        try withTemporaryDirectory { root throws in
            try Data("contents\n".utf8).write(to: URL(fileURLWithPath: root + "/work"))
            #expect(try KeyDirectory.regularFileContents(root + "/work") == Data("contents\n".utf8))
            #expect(mkdir(root + "/folder", 0o700) == 0)
            #expect(try KeyDirectory.regularFileContents(root + "/folder") == nil)
            #expect(symlink(root + "/work", root + "/link") == 0 && symlink(root + "/none", root + "/broken") == 0)
            #expect(try KeyDirectory.regularFileContents(root + "/link") == nil)
            #expect(try KeyDirectory.regularFileContents(root + "/broken") == nil)
            #expect(throws: SystemError(path: root + "/none", code: ENOENT)) {
                try KeyDirectory.regularFileContents(root + "/none")
            }
        }
    }

    @Test(.enabled(if: geteuid() != 0, "root reads every file"))
    func aFileThatCannotBeReadThrowsItsReason() throws {
        try withTemporaryDirectory { root throws in
            try Data("contents\n".utf8).write(to: URL(fileURLWithPath: root + "/work"))
            #expect(chmod(root + "/work", 0) == 0)
            #expect(throws: SystemError(path: root + "/work", code: EACCES)) {
                try KeyDirectory.regularFileContents(root + "/work")
            }
        }
    }
}
