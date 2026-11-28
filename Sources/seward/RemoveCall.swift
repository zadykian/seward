/// A call of `seward remove [--yes] NAME`, read from its arguments.
struct RemoveCall: Equatable {
    var name: KeyName
    /// Whether `--yes` is there: the question is skipped.
    var confirmed: Bool

    /// Reads the arguments after `remove`, or says why they make a wrong call.
    static func parse(_ arguments: [String]) -> Result<RemoveCall, WrongCall> {
        var confirmed = false
        var names: [String] = []
        for argument in arguments {
            if argument == "--yes" {
                guard !confirmed else { return .failure(WrongCall(reason: "--yes goes once")) }
                confirmed = true
            } else if argument.hasPrefix("-") {
                return .failure(WrongCall(reason: "remove takes no option \(argument)"))
            } else {
                names.append(argument)
            }
        }
        guard names.count == 1 else { return .failure(WrongCall(reason: "remove takes one NAME")) }
        guard let name = KeyName(names[0]) else { return .failure(WrongCall(reason: KeyName.rule)) }
        return .success(RemoveCall(name: name, confirmed: confirmed))
    }
}
