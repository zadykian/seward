@testable import seward

/// A terminal of the test's own: it notes each question and answers from a script.
final class ScriptedPrompt: Prompt {
    let isInteractive: Bool
    private var answers: [String?]
    private(set) var questions: [String] = []

    /// A terminal that answers with `answers` in turn, and with the input's end after them.
    init(_ answers: [String?] = [], isInteractive: Bool = true) {
        self.answers = answers
        self.isInteractive = isInteractive
    }

    func ask(_ question: String) -> String? {
        questions.append(question)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}
