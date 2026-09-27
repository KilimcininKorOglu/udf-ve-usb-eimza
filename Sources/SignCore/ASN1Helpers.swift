import Foundation
import SwiftASN1

/// OID DER encodings used by the CMS structures, precomputed as raw bytes.
enum OID {
    static let signedData = encode([1, 2, 840, 113549, 1, 7, 2])
    static let dataContent = encode([1, 2, 840, 113549, 1, 7, 1])
    static let sha256 = encode([2, 16, 840, 1, 101, 3, 4, 2, 1])
    static let rsaEncryption = encode([1, 2, 840, 113549, 1, 1, 1])
    static let contentType = encode([1, 2, 840, 113549, 1, 9, 3])
    static let messageDigest = encode([1, 2, 840, 113549, 1, 9, 4])
    static let signingTime = encode([1, 2, 840, 113549, 1, 9, 5])
    static let signingCertificateV2 = encode([1, 2, 840, 113549, 1, 9, 16, 2, 47])

    /// Encodes an OID (tag, length and base-128 body) as DER bytes.
    static func encode(_ parts: [UInt]) -> [UInt8] {
        var body: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for part in parts.dropFirst(2) { body.append(contentsOf: base128(part)) }
        return tlv(0x06, body)
    }

    private static func base128(_ value: UInt) -> [UInt8] {
        if value == 0 { return [0] }
        var groups: [UInt8] = []
        var v = value
        while v > 0 {
            groups.insert(UInt8(v & 0x7F), at: 0)
            v >>= 7
        }
        for index in 0..<(groups.count - 1) { groups[index] |= 0x80 }
        return groups
    }
}

/// Runs a serializer closure and returns the produced bytes.
func der(_ body: (inout DER.Serializer) throws -> Void) rethrows -> [UInt8] {
    var serializer = DER.Serializer()
    try body(&serializer)
    return serializer.serializedBytes
}

/// Wraps content in a tag with DER length encoding.
func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
    [tag] + lengthBytes(content.count) + content
}

private func lengthBytes(_ length: Int) -> [UInt8] {
    if length < 0x80 { return [UInt8(length)] }
    var value = length
    var bytes: [UInt8] = []
    while value > 0 {
        bytes.insert(UInt8(value & 0xFF), at: 0)
        value >>= 8
    }
    return [0x80 | UInt8(bytes.count)] + bytes
}

/// DER OCTET STRING around raw bytes.
func octetString(_ data: Data) -> [UInt8] {
    tlv(0x04, [UInt8](data))
}

/// DER UTCTime for the given date, `yyMMddHHmmssZ`.
func utcTime(_ date: Date) -> [UInt8] {
    var formatter = DateComponents()
    let calendar = Calendar(identifier: .gregorian)
    var utc = calendar
    utc.timeZone = TimeZone(identifier: "UTC")!
    formatter = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let text = String(
        format: "%02d%02d%02d%02d%02d%02dZ",
        (formatter.year ?? 2000) % 100, formatter.month ?? 1, formatter.day ?? 1,
        formatter.hour ?? 0, formatter.minute ?? 0, formatter.second ?? 0
    )
    return tlv(0x17, [UInt8](text.utf8))
}

/// DER AlgorithmIdentifier: SEQUENCE { OID, NULL? }.
func algorithmIdentifier(_ oidDER: [UInt8], includeNull: Bool) -> [UInt8] {
    tlv(0x30, oidDER + (includeNull ? [0x05, 0x00] : []))
}

/// Context-specific tag with the given number.
func contextTag(_ number: UInt) -> ASN1Identifier {
    ASN1Identifier(tagWithNumber: number, tagClass: .contextSpecific)
}

/// Normalises big-endian bytes into a positive DER INTEGER content.
func integerBytes(_ raw: [UInt8]) -> [UInt8] {
    var bytes = raw
    while bytes.count > 1, bytes.first == 0x00, (bytes[1] & 0x80) == 0 { bytes.removeFirst() }
    if bytes.isEmpty { return [0x00] }
    if bytes[0] & 0x80 != 0 { return [0x00] + bytes }
    return bytes
}

/// DER SET OF ordering: byte-wise ascending, shorter first on a prefix tie.
func derSetLess(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    for (a, b) in zip(lhs, rhs) where a != b { return a < b }
    return lhs.count < rhs.count
}
