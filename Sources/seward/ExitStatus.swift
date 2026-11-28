/// The status that each command exits with.
enum ExitStatus: Int32 {
    case success = 0
    case failure = 1
    /// A wrong call: an unknown command or arguments that the command does not take.
    case usage = 2
}
