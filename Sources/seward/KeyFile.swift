import Foundation

/// Where a key's private half lives.
enum Store: String, CaseIterable {
    /// The Mac's Secure Enclave. The key's file holds a form that this Mac's enclave alone unwraps.
    case enclave
    /// The key's file, which holds a software key whole.
    case file
}

/// The file of a key, `NAME` in the keys' directory: a line `seward-key VERSION STORE`, then the
/// key in base64, as its store represents it.
struct KeyFile: Equatable {
    /// The first word of the first line, by which seward knows its own files.
    static let tag = "seward-key"
    /// The version that this seward writes. It reads each one up to this.
    static let version = 1

    var store: Store
    /// CryptoKit's `dataRepresentation` of an enclave's key, or `rawRepresentation` of a software key.
    var key: Data

    /// Whether the file is seward's, by the first word of its first line, whatever its version.
    static func isSeward(_ contents: Data) -> Bool {
        let tag = Data(Self.tag.utf8)
        guard contents.starts(with: tag) else { return false }
        let next = contents.dropFirst(tag.count).first
        return next == nil || next == UInt8(ascii: " ") || next == UInt8(ascii: "\n")
    }

    /// Reads a file of any version up to this seward's.
    static func decode(_ contents: Data) throws -> KeyFile {
        guard isSeward(contents) else { throw KeyFileError.notSeward }
        // A newer version may change all that follows its number, so the number is read first, from
        // the bytes. One too big for an Int is newer still.
        let words = contents.prefix { $0 != UInt8(ascii: "\n") }
            .split(separator: UInt8(ascii: " "), omittingEmptySubsequences: false)
        guard words.count >= 2, let number = versionNumber(words[1]) else {
            throw KeyFileError.damaged("its first line names no version")
        }
        guard let version = Int(number), version <= Self.version else { throw KeyFileError.newer(version: number) }
        guard let text = String(data: contents, encoding: .utf8) else {
            throw KeyFileError.damaged("it is not text")
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count == 3, lines[2].isEmpty { lines.removeLast() }
        let header = lines[0].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard header.count == 3, let store = Store(rawValue: header[2]) else {
            throw KeyFileError.damaged("its first line names no store")
        }
        guard lines.count == 2, let key = Data(base64Encoded: String(lines[1])), !key.isEmpty else {
            throw KeyFileError.damaged("its second line is no key in base64")
        }
        return KeyFile(store: store, key: key)
    }

    /// The version that a first line's second word names: digits with no leading zero.
    private static func versionNumber(_ word: Data) -> String? {
        let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        guard let first = word.first, first != UInt8(ascii: "0"), word.allSatisfy({ digits.contains($0) })
        else { return nil }
        return String(bytes: word, encoding: .utf8)
    }

    /// The file as this seward writes it.
    func encoded() -> Data {
        Data("\(Self.tag) \(Self.version) \(store.rawValue)\n\(key.base64EncodedString())\n".utf8)
    }
}

/// Why a file does not read as a key of seward's.
enum KeyFileError: Error, Equatable, CustomStringConvertible {
    case notSeward
    /// A later seward wrote it: this one refuses it rather than guess at its form. The version is
    /// the file's digits, of any size.
    case newer(version: String)
    case damaged(String)

    var description: String {
        switch self {
        case .notSeward: "it is not a key of seward's"
        case .newer(let version): "its version, \(version), is newer than this seward reads: update seward"
        case .damaged(let reason): "the key's file is damaged: \(reason)"
        }
    }
}
