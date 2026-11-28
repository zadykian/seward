import Testing

@testable import seward

@Suite struct KeyNameTests {
    @Test(arguments: [
        "work", "Work-2", "a", "7", "id_ecdsa", "git.signing", "x.pubkey", "a.b-c_d",
        String(repeating: "a", count: 251),
    ])
    func theRuleTakesLettersDigitsDotsUnderscoresAndHyphens(name: String) {
        #expect(KeyName(name)?.value == name)
    }

    @Test(arguments: [
        "",
        ".hidden",
        "-flag",
        "_under",
        "two words",
        "a/b",
        "../up",
        "tab\tname",
        "ключ",
        "café",
        "work.pub",
        "seward.sock",
        "seward.lock",
        "WORK.PUB",
        "agent.Sock",
        String(repeating: "a", count: 252),
    ])
    func theRuleRefusesAnyOtherName(name: String) {
        #expect(KeyName(name) == nil)
    }
}
