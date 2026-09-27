import Foundation

/// Signature profile requested by the caller.
public enum SignatureType: String, Codable, Sendable {
    case cades = "CAdES"
    case xades = "XAdES"
}

/// One certificate available on the inserted card.
public struct CertificateEntry: Codable, Sendable {
    public let certificateId: String
    public let subject: String
    public let issuer: String
    public let serialNumber: String
    public let notBefore: Date
    public let notAfter: Date
    public let tckn: String?
    public let hasNonRepudiation: Bool
    public let certificateBase64: String

    public init(
        certificateId: String,
        subject: String,
        issuer: String,
        serialNumber: String,
        notBefore: Date,
        notAfter: Date,
        tckn: String?,
        hasNonRepudiation: Bool,
        certificateBase64: String
    ) {
        self.certificateId = certificateId
        self.subject = subject
        self.issuer = issuer
        self.serialNumber = serialNumber
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.tckn = tckn
        self.hasNonRepudiation = hasNonRepudiation
        self.certificateBase64 = certificateBase64
    }
}

/// Body of `POST /api/v1/signature/sign`.
public struct SignRequest: Codable, Sendable {
    public let certificateId: String
    public let password: String
    public let signatureType: SignatureType
    public let contentBase64: String
    public let transactionUUID: String?

    public init(
        certificateId: String,
        password: String,
        signatureType: SignatureType,
        contentBase64: String,
        transactionUUID: String? = nil
    ) {
        self.certificateId = certificateId
        self.password = password
        self.signatureType = signatureType
        self.contentBase64 = contentBase64
        self.transactionUUID = transactionUUID
    }
}

/// Result payload of a successful sign.
public struct SignResult: Codable, Sendable {
    public let signedDataBase64: String
    public let signatureType: SignatureType
    public let transactionUUID: String?

    public init(signedDataBase64: String, signatureType: SignatureType, transactionUUID: String?) {
        self.signedDataBase64 = signedDataBase64
        self.signatureType = signatureType
        self.transactionUUID = transactionUUID
    }
}
