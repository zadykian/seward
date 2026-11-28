import Foundation
import Testing

@testable import seward

@Suite struct RemoveTests {
    /// Runs `seward ARGUMENTS` on the keys' directory `ROOT/.ssh`, with the terminal `prompt`.
    private func seward(
        _ arguments: [String], in root: String, prompt: ScriptedPrompt = ScriptedPrompt()
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
}
