import Foundation

/// What a command reaches of the machine: the keys' directory and the Secure Enclave. A test
/// gives its own, so that it never touches the real `~/.ssh`.
struct Context {
    var keys: KeyDirectory
    var enclave: any Enclave

    /// The user's: `~/.ssh` and this Mac's Secure Enclave. `HOME` names the home where it is set,
    /// so that a test of the program gives a home of its own.
    static func user() -> Context {
        let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 }
        return Context(
            keys: KeyDirectory(path: (home ?? NSHomeDirectory()) + "/.ssh"), enclave: SecureEnclaveChip())
    }
}
