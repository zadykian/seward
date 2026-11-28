/// A key's name, which names its files in the keys' directory: `NAME` and `NAME.pub`.
struct KeyName: Hashable, CustomStringConvertible {
    /// The rule, as a wrong call says it.
    static let rule = """
        a key's name is up to \(longest) letters, digits, '.', '_' and '-', starts with a letter or \
        a digit, and ends in none of .pub, .sock and .lock
        """

    /// The longest name whose `.pub` fits in a file's name, 255 bytes on macOS.
    private static let longest = 251

    /// The ends of the agent's files and of a public key's, in any case, as macOS's file system
    /// ignores it by default.
    private static let reservedEnds = [".pub", ".sock", ".lock"]

    let value: String

    var description: String { value }

    /// The name, or nil where the rule refuses it.
    init?(_ value: String) {
        let scalars = value.unicodeScalars
        guard let first = scalars.first, Self.isLetterOrDigit(first), scalars.count <= Self.longest,
            scalars.allSatisfy({ Self.isLetterOrDigit($0) || "._-".unicodeScalars.contains($0) }),
            !Self.reservedEnds.contains(where: { value.lowercased().hasSuffix($0) })
        else { return nil }
        self.value = value
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }
}
