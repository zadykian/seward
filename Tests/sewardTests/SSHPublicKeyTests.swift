import Foundation
import Testing

@testable import seward

@Suite struct SSHPublicKeyTests {
    /// Stands for a point: the layout needs no point on the curve.
    private let point = Data([4] + (1...64).map { UInt8($0) })

    @Test func theBlobIsTheTypeTheCurveAndThePointEachWithItsLength() {
        let blob = SSHPublicKey(point: point).blob
        var expected = Data([0, 0, 0, 19])
        expected.append(Data("ecdsa-sha2-nistp256".utf8))
        expected.append(Data([0, 0, 0, 8]))
        expected.append(Data("nistp256".utf8))
        expected.append(Data([0, 0, 0, 65]))
        expected.append(point)
        #expect(blob == expected)
        #expect(blob.count == 104)
    }

    @Test func theLineIsTheTypeTheBlobInBase64AndTheName() {
        let key = SSHPublicKey(point: point)
        let line = key.line(comment: "work")
        #expect(line == "ecdsa-sha2-nistp256 \(key.blob.base64EncodedString()) work\n")
        #expect(line.hasPrefix("ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABB"))
    }
}
