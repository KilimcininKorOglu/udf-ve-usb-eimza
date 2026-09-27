import Foundation
import Crypto

/// Builds the PKCS#1 v1.5 DigestInfo structure a card signs for RSA.
public enum DigestInfo {
    /// Fixed DER prefix of a SHA-256 DigestInfo, followed by the 32-byte hash.
    private static let sha256Prefix: [UInt8] = [
        0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86,
        0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05,
        0x00, 0x04, 0x20,
    ]

    /// Wraps a 32-byte SHA-256 digest in its DigestInfo encoding.
    public static func sha256(_ digest: Data) -> Data {
        precondition(digest.count == 32, "SHA-256 digest must be 32 bytes")
        var out = Data(sha256Prefix)
        out.append(digest)
        return out
    }

    /// Hashes content with SHA-256 and returns the DigestInfo.
    public static func sha256DigestInfo(of content: Data) -> Data {
        let digest = SHA256.hash(data: content)
        return sha256(Data(digest))
    }
}
