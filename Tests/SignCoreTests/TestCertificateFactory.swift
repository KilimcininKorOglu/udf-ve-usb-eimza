import Foundation
import Crypto
import _CryptoExtras
import X509
import SwiftASN1
@testable import SignCore

/// Builds a self-signed certificate for tests, with a chosen TCKN in the
/// subject serialNumber attribute and an optional nonRepudiation KeyUsage.
enum TestCertificateFactory {
    /// An RSA signer with its self-signed certificate DER.
    struct RSAIdentity {
        let der: Data
        let key: _RSA.Signing.PrivateKey
    }

    static func makeRSA(tckn: String, nonRepudiation: Bool) throws -> RSAIdentity {
        let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let der = try makeDER(
            tckn: tckn,
            nonRepudiation: nonRepudiation,
            certKey: Certificate.PrivateKey(key),
            signatureAlgorithm: .sha256WithRSAEncryption
        )
        return RSAIdentity(der: der, key: key)
    }

    static func makeDER(tckn: String, nonRepudiation: Bool) throws -> Data {
        try makeDER(
            tckn: tckn,
            nonRepudiation: nonRepudiation,
            certKey: Certificate.PrivateKey(P256.Signing.PrivateKey()),
            signatureAlgorithm: .ecdsaWithSHA256
        )
    }

    private static func makeDER(
        tckn: String,
        nonRepudiation: Bool,
        certKey: Certificate.PrivateKey,
        signatureAlgorithm: Certificate.SignatureAlgorithm
    ) throws -> Data {

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
            signatureAlgorithm: signatureAlgorithm,
            extensions: extensions,
            issuerPrivateKey: certKey
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return Data(serializer.serializedBytes)
    }
}
