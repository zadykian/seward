import Foundation

/// The user at a terminal, whom a command asks before it deletes. A test gives its own.
protocol Prompt {
    /// Whether a person can answer: the input and the errors' stream are both a terminal.
    var isInteractive: Bool { get }

    /// Asks `question` and returns the line typed, or nil where the input ends first.
    func ask(_ question: String) -> String?
}

/// The process's terminal. The question goes to the errors' stream, which a script's output
/// never holds.
struct Terminal: Prompt {
    var isInteractive: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDERR_FILENO) == 1 }

    func ask(_ question: String) -> String? {
        FileHandle.standardError.write(Data(question.utf8))
        return readLine()
    }
}

/// A context with no terminal, as a test or a call from a script has.
struct NoTerminal: Prompt {
    var isInteractive: Bool { false }

    func ask(_ question: String) -> String? { nil }
}
