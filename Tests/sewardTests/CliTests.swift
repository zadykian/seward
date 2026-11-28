import Testing

@testable import seward

@Suite struct CliTests {
    /// A context that no call here reaches: a keys' directory that is missing.
    private let context = Context(keys: KeyDirectory(path: "/nonexistent/.ssh"), enclave: RecordingEnclave())

    @Test func versionPrintsTheVersionAndExitsZero() {
        let outcome = Cli.run(["--version"], context: context)
        #expect(outcome.status == .success)
        #expect(outcome.output == "seward \(Version.current)\n")
        #expect(outcome.errors.isEmpty)
    }

    @Test(arguments: [
        [],
        ["--help"],
        ["unknown"],
        ["--version", "extra"],
        ["extra", "--version"],
        ["extra", "keygen", "work"],
    ] as [[String]])
    func anyOtherCallExitsTwoWithTheUsage(arguments: [String]) {
        let outcome = Cli.run(arguments, context: context)
        #expect(outcome.status == .usage)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors == Cli.usage)
    }

    @Test func aWrongCallOfKeygenSaysWhyAboveTheUsage() {
        let outcome = Cli.run(["keygen"], context: context)
        #expect(outcome == Outcome(status: .usage, errors: "seward: keygen takes one NAME\n" + Cli.usage))
    }

    @Test func theStatusesAreZeroOneAndTwo() {
        #expect(ExitStatus.success.rawValue == 0)
        #expect(ExitStatus.failure.rawValue == 1)
        #expect(ExitStatus.usage.rawValue == 2)
    }
}
