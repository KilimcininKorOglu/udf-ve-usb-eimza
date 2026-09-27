import Foundation
import Crypto
import X509
import SwiftASN1

/// Parses an X.509 certificate into the entry exposed over the API.
public enum CertificateInfo {
    /// OID 2.5.4.5, the `serialNumber` naming attribute that carries the TCKN.
    static let serialNumberAttributeOID: ASN1ObjectIdentifier = [2, 5, 4, 5]

    public static func entry(fromDER der: Data) throws -> CertificateEntry {
        let certificate = try Certificate(derEncoded: [UInt8](der))
        let fingerprint = SHA256.hash(data: der)
        let certificateId = fingerprint.map { String(format: "%02x", $0) }.joined()

        return CertificateEntry(
            certificateId: certificateId,
            subject: String(describing: certificate.subject),
            issuer: String(describing: certificate.issuer),
            serialNumber: String(describing: certificate.serialNumber),
            notBefore: certificate.notValidBefore,
            notAfter: certificate.notValidAfter,
            tckn: tckn(from: certificate.subject),
            hasNonRepudiation: hasNonRepudiation(certificate),
            certificateBase64: der.base64EncodedString()
        )
    }

    /// True when the certificate's KeyUsage asserts nonRepudiation.
    static func hasNonRepudiation(_ certificate: Certificate) -> Bool {
        guard let usage = try? certificate.extensions.keyUsage else { return false }
        return usage.nonRepudiation
    }

    /// Extracts an 11-digit TCKN from the subject `serialNumber` attribute.
    static func tckn(from subject: DistinguishedName) -> String? {
        for rdn in subject {
            for attribute in rdn where attribute.type == serialNumberAttributeOID {
                let raw = String(describing: attribute.value)
                let digits = raw.filter(\.isNumber)
                if digits.count == 11 { return digits }
            }
        }
        return nil
    }
}
