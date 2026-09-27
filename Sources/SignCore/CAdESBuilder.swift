import Crypto
import Foundation
import SwiftASN1
import X509

/// Builds a CAdES-BES signature as a CMS SignedData structure, using an
/// external signing closure so the private key can stay on the card.
public struct CAdESBuilder: Sendable {
    public init() {}

    /// Produces the DER-encoded CMS ContentInfo.
    ///
    /// - Parameters:
    ///   - content: the data being signed.
    ///   - certificateDER: the signer certificate, DER encoded.
    ///   - attached: when true the content is embedded (opaque), otherwise detached.
    ///   - sign: signs the given signed-attributes bytes (SHA-256 then RSA
    ///     PKCS#1 v1.5) and returns the raw signature bytes.
    public func build(
        content: Data,
        certificateDER: Data,
        attached: Bool = false,
        sign: (Data) async throws -> Data
    ) async throws -> Data {
        let certificate = try Certificate(derEncoded: [UInt8](certificateDER))
        let contentDigest = Data(SHA256.hash(data: content))
        let certHash = Data(SHA256.hash(data: certificateDER))

        let attributes = signedAttributes(contentDigest: contentDigest, certHash: certHash)
        let toBeSigned = wrapAttributes(attributes, identifier: .set)
        let signature = try await sign(Data(toBeSigned))

        let embeddedAttrs = wrapAttributes(attributes, identifier: contextTag(0))
        let signer = try signerInfo(
            certificate: certificate,
            embeddedAttrs: embeddedAttrs,
            signature: signature
        )
        let signedData = signedDataBlock(
            certificateDER: certificateDER,
            content: content,
            attached: attached,
            signerInfo: signer
        )
        return contentInfo(signedData: signedData)
    }

    // MARK: Signed attributes

    private func signedAttributes(contentDigest: Data, certHash: Data) -> [[UInt8]] {
        var attrs: [[UInt8]] = []
        attrs.append(attribute(oidDER: OID.contentType, value: OID.dataContent))
        attrs.append(attribute(oidDER: OID.messageDigest, value: octetString(contentDigest)))
        attrs.append(attribute(oidDER: OID.signingTime, value: utcTime(Date())))
        attrs.append(attribute(oidDER: OID.signingCertificateV2, value: signingCertificateV2(certHash: certHash)))
        return attrs.sorted(by: derSetLess)
    }

    private func attribute(oidDER: [UInt8], value: [UInt8]) -> [UInt8] {
        der { serializer in
            serializer.appendConstructedNode(identifier: .sequence) { seq in
                seq.serializeRawBytes(oidDER)
                seq.appendConstructedNode(identifier: .set) { $0.serializeRawBytes(value) }
            }
        }
    }

    private func signingCertificateV2(certHash: Data) -> [UInt8] {
        der { serializer in
            serializer.appendConstructedNode(identifier: .sequence) { outer in
                outer.appendConstructedNode(identifier: .sequence) { certs in
                    certs.appendConstructedNode(identifier: .sequence) { ess in
                        ess.appendPrimitiveNode(identifier: .octetString) { $0.append(contentsOf: certHash) }
                    }
                }
            }
        }
    }

    private func wrapAttributes(_ attributes: [[UInt8]], identifier: ASN1Identifier) -> [UInt8] {
        der { serializer in
            serializer.appendConstructedNode(identifier: identifier) { node in
                for attribute in attributes { node.serializeRawBytes(attribute) }
            }
        }
    }

    // MARK: SignerInfo and SignedData

    private func signerInfo(certificate: Certificate, embeddedAttrs: [UInt8], signature: Data) throws -> [UInt8] {
        let issuerDER = try der { try $0.serialize(certificate.issuer) }
        let serial = integerBytes(Array(certificate.serialNumber.bytes))
        return der { serializer in
            serializer.appendConstructedNode(identifier: .sequence) { si in
                si.appendPrimitiveNode(identifier: .integer) { $0.append(0x01) }
                si.appendConstructedNode(identifier: .sequence) { ias in
                    ias.serializeRawBytes(issuerDER)
                    ias.appendPrimitiveNode(identifier: .integer) { $0.append(contentsOf: serial) }
                }
                si.serializeRawBytes(algorithmIdentifier(OID.sha256, includeNull: true))
                si.serializeRawBytes(embeddedAttrs)
                si.serializeRawBytes(algorithmIdentifier(OID.rsaEncryption, includeNull: true))
                si.appendPrimitiveNode(identifier: .octetString) { $0.append(contentsOf: signature) }
            }
        }
    }

    private func signedDataBlock(certificateDER: Data, content: Data, attached: Bool, signerInfo: [UInt8]) -> [UInt8] {
        der { serializer in
            serializer.appendConstructedNode(identifier: .sequence) { sd in
                sd.appendPrimitiveNode(identifier: .integer) { $0.append(0x01) }
                sd.appendConstructedNode(identifier: .set) {
                    $0.serializeRawBytes(algorithmIdentifier(OID.sha256, includeNull: true))
                }
                sd.appendConstructedNode(identifier: .sequence) { eci in
                    eci.serializeRawBytes(OID.dataContent)
                    if attached {
                        eci.appendConstructedNode(identifier: contextTag(0)) { explicit in
                            explicit.appendPrimitiveNode(identifier: .octetString) { $0.append(contentsOf: content) }
                        }
                    }
                }
                sd.appendConstructedNode(identifier: contextTag(0)) {
                    $0.serializeRawBytes([UInt8](certificateDER))
                }
                sd.appendConstructedNode(identifier: .set) { $0.serializeRawBytes(signerInfo) }
            }
        }
    }

    private func contentInfo(signedData: [UInt8]) -> Data {
        let bytes = der { serializer in
            serializer.appendConstructedNode(identifier: .sequence) { ci in
                ci.serializeRawBytes(OID.signedData)
                ci.appendConstructedNode(identifier: contextTag(0)) {
                    $0.serializeRawBytes(signedData)
                }
            }
        }
        return Data(bytes)
    }
}
