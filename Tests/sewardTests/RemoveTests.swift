import Foundation
import Testing

@testable import seward

@Suite struct RemoveTests {
    /// Runs `seward ARGUMENTS` on the keys' directory `ROOT/.ssh`, with the terminal `prompt`.
    private func seward(
        _ arguments: [String], in root: String, prompt: any Prompt = ScriptedPrompt()
    ) -> Outcome {
        let context = Context(
            keys: KeyDirectory(path: root + "/.ssh"), enclave: RecordingEnclave(), prompt: prompt)
        return Cli.run(arguments, context: context)
    }

    /// Makes the pairs `work` and `home` of the file store.
    private func makePairs(in root: String) {
        for name in ["work", "home"] {
            #expect(seward(["keygen", "--store", "file", name], in: root).status == .success)
        }
    }

    @Test func yesDeletesBothHalvesAndNothingElseWhereThereIsNoTerminal() throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let keys = root + "/.ssh"
            let prompt = ScriptedPrompt(isInteractive: false)
            let outcome = seward(["remove", "--yes", "work"], in: root, prompt: prompt)
            let expected = "removed \(keys)/work.pub\nremoved \(keys)/work\n"
            #expect(outcome == Outcome(status: .success, output: expected))
            #expect(try names(in: keys) == ["home", "home.pub"])
            #expect(prompt.questions.isEmpty)
        }
    }

    @Test func theNameTypedAgainDeletesTheKeyAfterAQuestionThatSaysWhatItRemoves() throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let keys = root + "/.ssh"
            let prompt = ScriptedPrompt(["work"])
            #expect(seward(["remove", "work"], in: root, prompt: prompt).status == .success)
            #expect(try names(in: keys) == ["home", "home.pub"])
            let question = try #require(prompt.questions.first)
            #expect(prompt.questions.count == 1)
            #expect(question.hasPrefix("Delete \(keys)/work.pub and \(keys)/work?\n"))
            #expect(question.contains("any other copy of the key's file, a backup's included, still signs"))
            #expect(question.contains("Revoke the key at GitHub and in authorized_keys"))
            #expect(question.hasSuffix("Type the name again to delete: "))
        }
    }

    @Test(arguments: [["home"], [""], [nil], []] as [[String?]])
    func anyOtherAnswerDeletesNothing(answers: [String?]) throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let before = try files(in: root + "/.ssh")
            let outcome = seward(["remove", "work"], in: root, prompt: ScriptedPrompt(answers))
            let errors = "seward: \(RemoveError.notConfirmed)\n"
            #expect(outcome == Outcome(status: .failure, errors: errors))
            #expect(try files(in: root + "/.ssh") == before)
        }
    }

    @Test func withNoTerminalAndNoYesRemoveIsAWrongCallThatDeletesNothing() throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let before = try files(in: root + "/.ssh")
            let prompt = ScriptedPrompt(["work"], isInteractive: false)
            let outcome = seward(["remove", "work"], in: root, prompt: prompt)
            let reason = "seward: remove asks on a terminal: where there is none, add --yes\n"
            #expect(outcome == Outcome(status: .usage, errors: reason + Cli.usage))
            #expect(try files(in: root + "/.ssh") == before)
            #expect(prompt.questions.isEmpty)
        }
    }

    @Test(arguments: ["work", "work.pub"])
    func eitherHalfAloneIsDeleted(half: String) throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let keys = root + "/.ssh"
            let other = half == "work" ? "work.pub" : "work"
            #expect(unlink(keys + "/" + other) == 0)
            let outcome = seward(["remove", "--yes", "work"], in: root)
            #expect(outcome == Outcome(status: .success, output: "removed \(keys)/\(half)\n"))
            #expect(try names(in: keys) == ["home", "home.pub"])
        }
    }

    @Test func aKeyWithNoFileIsAFailureThatAsksNothing() throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let prompt = ScriptedPrompt(["absent"])
            let outcome = seward(["remove", "absent"], in: root, prompt: prompt)
            let name = try #require(KeyName("absent"))
            #expect(outcome == Outcome(status: .failure, errors: "seward: \(RemoveError.missing(name))\n"))
            #expect(prompt.questions.isEmpty)
            #expect(try names(in: root + "/.ssh") == ["home", "home.pub", "work", "work.pub"])
        }
    }

    @Test(arguments: ["file", "link", "directory"])
    func aNameWhoseFileIsNotSewardsDeletesNothing(kind: String) throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let keys = root + "/.ssh"
            #expect(unlink(keys + "/work") == 0)
            switch kind {
            case "file": try write("-----BEGIN OPENSSH PRIVATE KEY-----\n", to: keys + "/work")
            case "link": #expect(symlink(keys + "/home", keys + "/work") == 0)
            default:
                try FileManager.default.createDirectory(atPath: keys + "/work", withIntermediateDirectories: false)
            }
            let before = try names(in: keys)
            let outcome = seward(["remove", "--yes", "work"], in: root)
            let errors = "seward: \(RemoveError.notSeward(keys + "/work"))\n"
            #expect(outcome == Outcome(status: .failure, errors: errors))
            #expect(try names(in: keys) == before)
            #expect(try names(in: keys).contains("work.pub"))
            #expect(try names(in: keys).contains("home"))
        }
    }

    @Test func aFileReplacedWhileThePersonTypesIsNotDeleted() throws {
        try withTemporaryDirectory { root throws in
            makePairs(in: root)
            let keys = root + "/.ssh"
            let prompt = ReplacingPrompt(answer: "work") {
                _ = unlink(keys + "/work")
                try? write("-----BEGIN OPENSSH PRIVATE KEY-----\n", to: keys + "/work")
            }
            let outcome = seward(["remove", "work"], in: root, prompt: prompt)
            let errors = "seward: \(RemoveError.notSeward(keys + "/work"))\n"
            #expect(outcome == Outcome(status: .failure, errors: errors))
            #expect(try names(in: keys) == ["home", "home.pub", "work", "work.pub"])
        }
    }
}

/// A terminal that runs `beforeAnswer` and then gives `answer`, as a person does after a pause.
private final class ReplacingPrompt: Prompt {
    let isInteractive = true
    private let answer: String
    private let beforeAnswer: () -> Void

    init(answer: String, beforeAnswer: @escaping () -> Void) {
        self.answer = answer
        self.beforeAnswer = beforeAnswer
    }

    func ask(_ question: String) -> String? {
        beforeAnswer()
        return answer
    }
}
