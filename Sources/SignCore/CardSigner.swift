import Foundation

/// Drives PIN verification and the on-card RSA signature computation.
///
/// The private key never leaves the card: the digest is sent with PSO and the
/// card returns the raw signature bytes.
public struct CardSigner: Sendable {
    /// RSA with PKCS#1 v1.5 padding, the common algorithm reference for
    /// qualified signature cards.
    public static let algorithmRSAPKCS1: UInt8 = 0x02

    private let session: any CardSession

    public init(session: any CardSession) {
        self.session = session
    }

    /// Verifies the PIN, mapping the card status word to a typed error.
    public func verifyPIN(_ pin: String, reference: UInt8 = 0x00) async throws {
        let response = try await session.transmit(
            ApduRecipes.verifyPIN(Data(pin.utf8), reference: reference)
        )
        if response.isSuccess { return }
        switch response.statusWord {
        case 0x63_C0...0x63_CF:
            throw CardError.pinIncorrect(retriesLeft: Int(response.sw2 & 0x0F))
        case 0x6983, 0x6984:
            throw CardError.pinIncorrect(retriesLeft: 0)
        default:
            throw CardError.apduFailed(response.statusWord)
        }
    }

    /// Signs a SHA-256 digest and returns the raw signature bytes.
    public func signSHA256(
        digest: Data,
        keyReference: UInt8,
        algorithm: UInt8 = CardSigner.algorithmRSAPKCS1
    ) async throws -> Data {
        try await session.selectExpectingSuccess(
            ApduRecipes.mseSetDigitalSignature(keyReference: keyReference, algorithm: algorithm)
        )
        let payload = DigestInfo.sha256(digest)
        let response = try await session.transmit(ApduRecipes.computeSignature(payload))
        return try await collectSignature(response)
    }

    /// Reads the signature, following a 61xx "more data" status via GET RESPONSE.
    private func collectSignature(_ response: APDUResponse) async throws -> Data {
        if response.isSuccess { return response.data }
        guard response.sw1 == 0x61 else { throw CardError.apduFailed(response.statusWord) }
        var output = response.data
        var remaining = response.sw2
        while remaining != 0 {
            let next = try await session.transmit(ApduRecipes.getResponse(length: remaining))
            output.append(next.data)
            if next.isSuccess { break }
            guard next.sw1 == 0x61 else { throw CardError.apduFailed(next.statusWord) }
            remaining = next.sw2
        }
        return output
    }
}
