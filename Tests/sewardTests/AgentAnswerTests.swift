import Foundation
import Testing

@testable import seward

@Suite struct AgentAnswerTests {
    @Test func anAnswerWithNoKeyHoldsACountOfZero() {
        #expect(AgentAnswer.identities([]) == Data([12, 0, 0, 0, 0]))
    }

    @Test func anAnswerHoldsEachKeysBlobAndName() {
        let keys = [
            AgentKey(name: "work", blob: Data([1, 2])) { _ in Data() },
            AgentKey(name: "home", blob: Data([3])) { _ in Data() },
        ]
        var expected = Data([12, 0, 0, 0, 2])
        expected += Data([0, 0, 0, 2, 1, 2, 0, 0, 0, 4]) + Data("work".utf8)
        expected += Data([0, 0, 0, 1, 3, 0, 0, 0, 4]) + Data("home".utf8)
        #expect(AgentAnswer.identities(keys) == expected)
    }

    @Test(arguments: [
        ([0x7f], [0, 0, 0, 1, 0x7f]),
        ([0x80], [0, 0, 0, 2, 0, 0x80]),
        ([0, 0, 0x01, 0xff], [0, 0, 0, 2, 0x01, 0xff]),
        ([0, 0xff], [0, 0, 0, 2, 0, 0xff]),
        ([0, 0], [0, 0, 0, 0]),
    ] as [([UInt8], [UInt8])])
    func aNumberTakesNoZeroBeforeItButForASignBit(magnitude: [UInt8], mpint: [UInt8]) {
        #expect(AgentAnswer.mpint(Data(magnitude)) == Data(mpint))
    }

    @Test func aSignatureHoldsItsTypeThenRAndSAsNumbers() {
        let first = Data([0x80] + [UInt8](repeating: 1, count: 31))
        let second = Data([0, 0x42] + [UInt8](repeating: 2, count: 30))
        let numbers = Data([0, 0, 0, 33, 0]) + first + Data([0, 0, 0, 31]) + second.dropFirst()
        var blob = Data([0, 0, 0, 19]) + Data("ecdsa-sha2-nistp256".utf8)
        blob += AgentWire.uint32(UInt32(numbers.count)) + numbers
        let expected = Data([14]) + AgentWire.uint32(UInt32(blob.count)) + blob
        #expect(AgentAnswer.signature(first + second) == expected)
    }
}
