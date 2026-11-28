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
}
