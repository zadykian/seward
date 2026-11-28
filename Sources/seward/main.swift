import Foundation

let outcome = Cli.run(Array(CommandLine.arguments.dropFirst()), context: .user())
FileHandle.standardOutput.write(Data(outcome.output.utf8))
FileHandle.standardError.write(Data(outcome.errors.utf8))
exit(outcome.status.rawValue)
