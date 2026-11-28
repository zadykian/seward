import Testing

@testable import seward

@Suite struct RemoveCallTests {
    @Test(arguments: [
        (["work"], false),
        (["--yes", "work"], true),
        (["work", "--yes"], true),
    ] as [([String], Bool)])
    func aNameAndAYesMakeACall(arguments: [String], confirmed: Bool) throws {
        let name = try #require(KeyName("work"))
        #expect(try RemoveCall.parse(arguments).get() == RemoveCall(name: name, confirmed: confirmed))
    }

    @Test(arguments: [
        ([], "remove takes one NAME"),
        (["--yes"], "remove takes one NAME"),
        (["work", "home"], "remove takes one NAME"),
        (["--yes", "--yes", "work"], "--yes goes once"),
        (["-y", "work"], "remove takes no option -y"),
        (["--force", "work"], "remove takes no option --force"),
        (["work.pub"], KeyName.rule),
        (["../work"], KeyName.rule),
    ] as [([String], String)])
    func anyOtherCallIsWrongAndSaysWhy(arguments: [String], reason: String) {
        #expect(throws: WrongCall(reason: reason)) { try RemoveCall.parse(arguments).get() }
    }
}
