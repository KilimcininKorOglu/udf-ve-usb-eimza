import Foundation
import Crypto
import X509

/// Builds an enveloping XAdES-BES signature (XML-DSig plus SignedProperties),
/// signing with an external closure so the card key never leaves the card.
public struct XAdESBuilder: Sendable {
    private enum NS {
        static let ds = "http://www.w3.org/2000/09/xmldsig#"
        static let xades = "http://uri.etsi.org/01903/v1.3.2#"
        static let c14n = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
        static let sha256 = "http://www.w3.org/2001/04/xmlenc#sha256"
        static let rsaSHA256 = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
        static let signedProps = "http://uri.etsi.org/01903#SignedProperties"
    }

    public init() {}

    /// Produces the XAdES XML document as UTF-8 bytes.
    public func build(
        content: Data,
        certificateDER: Data,
        sign: (Data) async throws -> Data
    ) async throws -> Data {
        let certificate = try Certificate(derEncoded: [UInt8](certificateDER))
        let ids = Identifiers()

        let objectXML = objectElement(id: ids.object, contentBase64: content.base64EncodedString())
        let objectDigest = try digestBase64(objectXML)

        let signedProps = signedPropertiesElement(
            id: ids.signedProperties,
            certificate: certificate,
            certificateDER: certificateDER
        )
        let signedPropsDigest = try digestBase64(signedProps)

        let signedInfo = signedInfoElement(
            ids: ids,
            objectDigest: objectDigest,
            signedPropsDigest: signedPropsDigest
        )
        let toBeSigned = try Canonicalizer.canonicalize(signedInfo)
        let signatureValue = try await sign(toBeSigned).base64EncodedString()

        let document = assemble(ids: ids, parts: SignatureParts(
            signedInfo: signedInfo,
            signatureValue: signatureValue,
            certificateBase64: certificateDER.base64EncodedString(),
            objectXML: objectXML,
            signedProperties: signedProps
        ))
        return Data(document.utf8)
    }

    private func digestBase64(_ xml: String) throws -> String {
        let canonical = try Canonicalizer.canonicalize(xml)
        return Data(SHA256.hash(data: canonical)).base64EncodedString()
    }

    // MARK: Element builders

    private func objectElement(id: String, contentBase64: String) -> String {
        "<ds:Object xmlns:ds=\"\(NS.ds)\" Id=\"\(id)\">\(contentBase64)</ds:Object>"
    }

    private func signedPropertiesElement(id: String, certificate: Certificate, certificateDER: Data) -> String {
        let certDigest = Data(SHA256.hash(data: certificateDER)).base64EncodedString()
        let issuer = xmlEscape(String(describing: certificate.issuer))
        let serial = decimalString(Array(certificate.serialNumber.bytes))
        let time = iso8601(Date())
        return """
        <xades:SignedProperties xmlns:xades="\(NS.xades)" xmlns:ds="\(NS.ds)" Id="\(id)">\
        <xades:SignedSignatureProperties>\
        <xades:SigningTime>\(time)</xades:SigningTime>\
        <xades:SigningCertificate><xades:Cert>\
        <xades:CertDigest>\
        <ds:DigestMethod Algorithm="\(NS.sha256)"></ds:DigestMethod>\
        <ds:DigestValue>\(certDigest)</ds:DigestValue>\
        </xades:CertDigest>\
        <xades:IssuerSerial>\
        <ds:X509IssuerName>\(issuer)</ds:X509IssuerName>\
        <ds:X509SerialNumber>\(serial)</ds:X509SerialNumber>\
        </xades:IssuerSerial>\
        </xades:Cert></xades:SigningCertificate>\
        </xades:SignedSignatureProperties>\
        </xades:SignedProperties>
        """
    }

    private func signedInfoElement(ids: Identifiers, objectDigest: String, signedPropsDigest: String) -> String {
        """
        <ds:SignedInfo xmlns:ds="\(NS.ds)">\
        <ds:CanonicalizationMethod Algorithm="\(NS.c14n)"></ds:CanonicalizationMethod>\
        <ds:SignatureMethod Algorithm="\(NS.rsaSHA256)"></ds:SignatureMethod>\
        <ds:Reference URI="#\(ids.object)">\
        <ds:Transforms><ds:Transform Algorithm="\(NS.c14n)"></ds:Transform></ds:Transforms>\
        <ds:DigestMethod Algorithm="\(NS.sha256)"></ds:DigestMethod>\
        <ds:DigestValue>\(objectDigest)</ds:DigestValue>\
        </ds:Reference>\
        <ds:Reference URI="#\(ids.signedProperties)" Type="\(NS.signedProps)">\
        <ds:Transforms><ds:Transform Algorithm="\(NS.c14n)"></ds:Transform></ds:Transforms>\
        <ds:DigestMethod Algorithm="\(NS.sha256)"></ds:DigestMethod>\
        <ds:DigestValue>\(signedPropsDigest)</ds:DigestValue>\
        </ds:Reference>\
        </ds:SignedInfo>
        """
    }

    private func assemble(ids: Identifiers, parts: SignatureParts) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>\
        <ds:Signature xmlns:ds="\(NS.ds)" Id="\(ids.signature)">\
        \(parts.signedInfo)\
        <ds:SignatureValue>\(parts.signatureValue)</ds:SignatureValue>\
        <ds:KeyInfo><ds:X509Data>\
        <ds:X509Certificate>\(parts.certificateBase64)</ds:X509Certificate>\
        </ds:X509Data></ds:KeyInfo>\
        \(parts.objectXML)\
        <ds:Object><xades:QualifyingProperties xmlns:xades="\(NS.xades)" Target="#\(ids.signature)">\
        \(parts.signedProperties)\
        </xades:QualifyingProperties></ds:Object>\
        </ds:Signature>
        """
    }
}

/// The already-built body fragments assembled into the final XAdES document.
private struct SignatureParts {
    let signedInfo: String
    let signatureValue: String
    let certificateBase64: String
    let objectXML: String
    let signedProperties: String
}

/// Stable element identifiers for one signature.
private struct Identifiers {
    let signature = "Signature-\(UUID().uuidString)"
    let object = "Object-\(UUID().uuidString)"
    let signedProperties = "SignedProperties-\(UUID().uuidString)"
}

/// Converts unsigned big-endian bytes to a base-10 string.
func decimalString(_ bytes: [UInt8]) -> String {
    var digits = [0]
    for byte in bytes {
        var carry = Int(byte)
        for index in digits.indices {
            let value = digits[index] * 256 + carry
            digits[index] = value % 10
            carry = value / 10
        }
        while carry > 0 {
            digits.append(carry % 10)
            carry /= 10
        }
    }
    return digits.reversed().map(String.init).joined()
}

/// Escapes text for inclusion in element content.
func xmlEscape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// ISO 8601 UTC timestamp without fractional seconds.
func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
}
