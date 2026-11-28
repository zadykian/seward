/// What a call prints on each stream and the status it exits with.
struct Outcome: Equatable {
    var status: ExitStatus
    var output = ""
    var errors = ""
}

/// The command line, as a function of its arguments and its context, so that a test calls it
/// with no process.
enum Cli {
    static let usage = """
        usage: seward keygen [--store enclave|file] NAME
               seward --version

        """

    /// Runs the call. `arguments` leaves out the program's name.
    static func run(_ arguments: [String], context: Context) -> Outcome {
        if arguments == ["--version"] {
            return Outcome(status: .success, output: "seward \(Version.current)\n")
        }
        if arguments.first == "keygen" {
            return Keygen.run(Array(arguments.dropFirst()), context: context)
        }
        return Outcome(status: .usage, errors: usage)
    }
}
