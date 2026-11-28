/// What a call prints on each stream and the status it exits with.
struct Outcome: Equatable {
    var status: ExitStatus
    var output = ""
    var errors = ""
}

/// The command line, as a function of its arguments, so that a test calls it with no process.
enum Cli {
    static let usage = "usage: seward --version\n"

    /// Runs the call. `arguments` leaves out the program's name.
    static func run(_ arguments: [String]) -> Outcome {
        if arguments == ["--version"] {
            return Outcome(status: .success, output: "seward \(Version.current)\n")
        }
        return Outcome(status: .usage, errors: usage)
    }
}
