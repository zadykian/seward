/// A call of `seward keygen [--store enclave|file] NAME`, read from its arguments.
struct KeygenCall: Equatable {
    var name: KeyName
    /// The store of a new key: a key in place keeps its own.
    var store: Store

    /// Reads the arguments after `keygen`, or says why they make a wrong call.
    static func parse(_ arguments: [String]) -> Result<KeygenCall, WrongCall> {
        var store: Store?
        var names: [String] = []
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            if argument == "--store" {
                guard store == nil, let value = rest.popFirst(), let picked = Store(rawValue: value) else {
                    return .failure(WrongCall(reason: "--store takes enclave or file, once"))
                }
                store = picked
            } else if argument.hasPrefix("-") {
                return .failure(WrongCall(reason: "keygen takes no option \(argument)"))
            } else {
                names.append(argument)
            }
        }
        guard names.count == 1 else { return .failure(WrongCall(reason: "keygen takes one NAME")) }
        guard let name = KeyName(names[0]) else { return .failure(WrongCall(reason: KeyName.rule)) }
        return .success(KeygenCall(name: name, store: store ?? .enclave))
    }
}

/// Why a call is wrong, which it says above the usage.
struct WrongCall: Error, Equatable {
    var reason: String
}
