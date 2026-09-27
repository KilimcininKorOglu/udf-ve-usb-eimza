import Foundation
import Crypto
import X509
import SwiftASN1
@testable import SignCore

/// Builds a self-signed certificate for tests, with a chosen TCKN in the
/// subject serialNumber attribute and an optional nonRepudiation KeyUsage.
enum TestCertificateFactory {
    static func makeDER(tckn: String, nonRepudiation: Bool) throws -> Data {
        let key = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(key)

        let serialAttribute = try RelativeDistinguishedName.Attribute(
            type: CertificateInfo.serialNumberAttributeOID,
            utf8String: tckn
        )
        let name = try DistinguishedName {
            CommonName("Test Kullanıcı")
        }
        var rdns = Array(name)
        rdns.append(RelativeDistinguishedName([serialAttribute]))
        let subject = DistinguishedName(rdns)

        let extensions = try Certificate.Extensions {
            KeyUsage(nonRepudiation: nonRepudiation)
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: certKey.publicKey,
            notValidBefore: Date().addingTimeInterval(-60),
            notValidAfter: Date().addingTimeInterval(3600),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: certKey
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return Data(serializer.serializedBytes)
    }
}
