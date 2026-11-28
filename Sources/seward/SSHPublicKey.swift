import Foundation

/// An `ecdsa-sha2-nistp256` public key in ssh's forms, RFC 5656's: the blob that the agent's
/// messages carry, and the line of a `.pub` file.
struct SSHPublicKey: Equatable {
    static let type = "ecdsa-sha2-nistp256"
    static let curve = "nistp256"

    /// The curve's point in X9.63's uncompressed form, 65 bytes, as CryptoKit's
    /// `x963Representation` gives it.
    let point: Data

    /// The type, the curve and the point, each as ssh's string: its length in four bytes, big
    /// endian, then its bytes.
    var blob: Data {
        var blob = Data()
        for field in [Data(Self.type.utf8), Data(Self.curve.utf8), point] {
            let length = UInt32(field.count)
            blob.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: length >> $0) })
            blob.append(field)
        }
        return blob
    }

    /// The line of a `.pub` file: the type, the blob in base64, and the key's name as its comment.
    func line(comment: String) -> String {
        "\(Self.type) \(blob.base64EncodedString()) \(comment)\n"
    }
}
