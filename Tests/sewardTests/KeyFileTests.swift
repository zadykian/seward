import Foundation
import Testing

@testable import seward

@Suite struct KeyFileTests {
    /// Stands for a key: the layout's tests need no real one.
    private let key = Data((1...32).map { UInt8($0) })

    @Test(arguments: Store.allCases)
    func aFileReadsBackAsItWasWritten(store: Store) throws {
        let file = KeyFile(store: store, key: key)
        let text = "seward-key 1 \(store.rawValue)\n\(key.base64EncodedString())\n"
        #expect(file.encoded() == Data(text.utf8))
        #expect(try KeyFile.decode(file.encoded()) == file)
    }

    @Test func versionOneStillReadsWithOrWithoutItsLastNewline() throws {
        let text = "seward-key 1 enclave\n\(key.base64EncodedString())"
        #expect(try KeyFile.decode(Data(text.utf8)) == KeyFile(store: .enclave, key: key))
        #expect(try KeyFile.decode(Data((text + "\n").utf8)) == KeyFile(store: .enclave, key: key))
    }

    @Test(arguments: [
        (Data("seward-key 2 enclave\nAAAA\n".utf8), "2"),
        (Data("seward-key 2 tpm\n".utf8), "2"),
        (Data("seward-key 17\n".utf8), "17"),
        (Data("seward-key 2 enclave\n".utf8) + Data([0xff, 0xfe]), "2"),
        (Data("seward-key 2 ".utf8) + Data([0xff]), "2"),
        (Data("seward-key 9223372036854775808 enclave\nAAAA\n".utf8), "9223372036854775808"),
    ] as [(Data, String)])
    func aNewerVersionIsRefusedByItsNumberWhateverFollowsIt(contents: Data, version: String) {
        #expect(throws: KeyFileError.newer(version: version)) { try KeyFile.decode(contents) }
        #expect(KeyFileError.newer(version: version).description.contains("version, \(version), is newer"))
    }

    @Test(arguments: [
        "seward-key",
        "seward-key\nAAAA\n",
        "seward-key 1\nAAAA\n",
        "seward-key one file\nAAAA\n",
        "seward-key 0 file\nAAAA\n",
        "seward-key 01 file\nAAAA\n",
        "seward-key -1 file\nAAAA\n",
        "seward-key 1 tpm\nAAAA\n",
        "seward-key 1 file extra\nAAAA\n",
        "seward-key 1 file\n",
        "seward-key 1 file\n\n",
        "seward-key 1 file\nnot base64!\n",
        "seward-key 1 file\nAAAA\nAAAA\n",
        "seward-key 1 file\nAAAA\n\n",
    ])
    func aFileOfSewardsThatDoesNotReadIsDamaged(text: String) {
        #expect(KeyFile.isSeward(Data(text.utf8)))
        let error = #expect(throws: KeyFileError.self) { try KeyFile.decode(Data(text.utf8)) }
        #expect(error?.description.hasPrefix("the key's file is damaged") == true)
    }

    @Test func aFileOfSewardsThatIsNotTextIsDamaged() {
        let contents = Data("seward-key 1 file\n".utf8) + Data([0xff, 0xfe])
        #expect(throws: KeyFileError.damaged("it is not text")) { try KeyFile.decode(contents) }
    }

    @Test(arguments: [
        "",
        "ssh-rsa AAAA work\n",
        "-----BEGIN OPENSSH PRIVATE KEY-----\n",
        "seward-keys 1 file\nAAAA\n",
        " seward-key 1 file\nAAAA\n",
        "Host *\n",
    ])
    func anyOtherFileIsNotSewards(text: String) {
        #expect(!KeyFile.isSeward(Data(text.utf8)))
        #expect(throws: KeyFileError.notSeward) { try KeyFile.decode(Data(text.utf8)) }
    }
}
