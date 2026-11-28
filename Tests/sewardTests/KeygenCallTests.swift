import Testing

@testable import seward

@Suite struct KeygenCallTests {
    @Test(arguments: [
        (["work"], .enclave),
        (["--store", "enclave", "work"], .enclave),
        (["--store", "file", "work"], .file),
        (["work", "--store", "file"], .file),
    ] as [([String], Store)])
    func aNameAndAStoreMakeACall(arguments: [String], store: Store) throws {
        let name = try #require(KeyName("work"))
        #expect(try KeygenCall.parse(arguments).get() == KeygenCall(name: name, store: store))
    }

    @Test(arguments: [
        ([], "keygen takes one NAME"),
        (["work", "home"], "keygen takes one NAME"),
        (["--store"], "--store takes enclave or file, once"),
        (["--store", "tpm", "work"], "--store takes enclave or file, once"),
        (["--store", "file", "--store", "file", "work"], "--store takes enclave or file, once"),
        (["work", "--store"], "--store takes enclave or file, once"),
        (["--store=file", "work"], "keygen takes no option --store=file"),
        (["-f", "work"], "keygen takes no option -f"),
        (["work.pub"], KeyName.rule),
        ([".work"], KeyName.rule),
    ] as [([String], String)])
    func anyOtherCallIsWrongAndSaysWhy(arguments: [String], reason: String) {
        #expect(throws: WrongCall(reason: reason)) { try KeygenCall.parse(arguments).get() }
    }
}
