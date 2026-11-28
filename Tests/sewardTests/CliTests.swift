import Testing

@testable import seward

@Suite struct CliTests {
    @Test func versionPrintsTheVersionAndExitsZero() {
        let outcome = Cli.run(["--version"])
        #expect(outcome.status == .success)
        #expect(outcome.output == "seward \(Version.current)\n")
        #expect(outcome.errors.isEmpty)
    }

    @Test(arguments: [
        [],
        ["--help"],
        ["list"],
        ["--version", "extra"],
        ["extra", "--version"],
    ] as [[String]])
    func anyOtherCallExitsTwoWithTheUsage(arguments: [String]) {
        let outcome = Cli.run(arguments)
        #expect(outcome.status == .usage)
        #expect(outcome.output.isEmpty)
        #expect(outcome.errors == Cli.usage)
    }

    @Test func theStatusesAreZeroOneAndTwo() {
        #expect(ExitStatus.success.rawValue == 0)
        #expect(ExitStatus.failure.rawValue == 1)
        #expect(ExitStatus.usage.rawValue == 2)
    }
}
