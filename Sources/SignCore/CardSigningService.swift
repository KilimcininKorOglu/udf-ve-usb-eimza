import Foundation
import Crypto

/// Wires the card transport, PKCS#15 reader and signature builders behind the
/// loopback endpoints.
public struct CardSigningService: SigningService {
    /// Default private-key reference; card layouts that differ expose it in
    /// the PKCS#15 PrKDF and can override this.
    public static let defaultKeyReference: UInt8 = 0x01

    private let transport: any CardTransport
    private let keyReference: UInt8
    private let pinReference: UInt8

    public init(
        transport: any CardTransport,
        keyReference: UInt8 = CardSigningService.defaultKeyReference,
        pinReference: UInt8 = 0x00
    ) {
        self.transport = transport
        self.keyReference = keyReference
        self.pinReference = pinReference
    }

    public func listCertificates() async -> Envelope<[CertificateEntry]> {
        do {
            let entries = try await readEntries()
            return .ok(entries)
        } catch {
            return .failure(message(for: error))
        }
    }

    public func sign(_ request: SignRequest) async -> Envelope<SignResult> {
        guard !request.certificateId.isEmpty, !request.password.isEmpty else {
            return .failure("certificateId/password gerekli")
        }
        do {
            let result = try await performSign(request)
            return .ok(result)
        } catch {
            return .failure(message(for: error))
        }
    }

    public func cardStatusStream() -> AsyncStream<CardStatusEvent> {
        AsyncStream { continuation in
            let task = Task {
                var last: CardStatus?
                while !Task.isCancelled {
                    let event = await currentStatus()
                    if event.status != last {
                        continuation.yield(event)
                        last = event.status
                    }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Flow

    private func readEntries() async throws -> [CertificateEntry] {
        let session = try await transport.openSession(slotName: nil)
        defer { Task { await session.end() } }
        let reader = Pkcs15Reader(session: session)
        let derList = try await reader.certificates()
        return derList.compactMap { try? CertificateInfo.entry(fromDER: $0) }
    }

    private func performSign(_ request: SignRequest) async throws -> SignResult {
        guard let content = Data(base64Encoded: request.contentBase64) else {
            throw CardError.parse("içerik base64 değil")
        }
        let session = try await transport.openSession(slotName: nil)
        defer { Task { await session.end() } }

        let derList = try await Pkcs15Reader(session: session).certificates()
        guard let certificateDER = matchCertificate(derList, id: request.certificateId) else {
            throw CardError.parse("sertifika bulunamadı")
        }

        let signer = CardSigner(session: session)
        try await signer.verifyPIN(request.password, reference: pinReference)

        let signed = try await produce(
            type: request.signatureType,
            content: content,
            certificateDER: certificateDER,
            signer: signer
        )
        return SignResult(
            signedDataBase64: signed.base64EncodedString(),
            signatureType: request.signatureType,
            transactionUUID: request.transactionUUID
        )
    }

    private func produce(
        type: SignatureType,
        content: Data,
        certificateDER: Data,
        signer: CardSigner
    ) async throws -> Data {
        let sign: (Data) async throws -> Data = { message in
            let digest = Data(SHA256.hash(data: message))
            return try await signer.signSHA256(digest: digest, keyReference: keyReference)
        }
        switch type {
        case .cades:
            return try await CAdESBuilder().build(content: content, certificateDER: certificateDER, sign: sign)
        case .xades:
            return try await XAdESBuilder().build(content: content, certificateDER: certificateDER, sign: sign)
        }
    }

    private func matchCertificate(_ derList: [Data], id: String) -> Data? {
        derList.first { Data(SHA256.hash(data: $0)).map { String(format: "%02x", $0) }.joined() == id }
    }

    private func currentStatus() async -> CardStatusEvent {
        do {
            let slots = try await transport.listSlots()
            guard let name = slots.first else {
                return CardStatusEvent(status: .absent, message: "Kart/okuyucu bulunamadı")
            }
            let session = try await transport.openSession(slotName: name)
            await session.end()
            return CardStatusEvent(status: .present, readerName: name)
        } catch CardError.cardUnavailable, CardError.noReader {
            return CardStatusEvent(status: .absent, message: "Kart bekleniyor")
        } catch {
            return CardStatusEvent(status: .error, message: message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case CardError.slotManagerUnavailable: return "Okuyucu servisi kullanılamıyor"
        case CardError.noReader, CardError.cardUnavailable: return "Kart/okuyucu bulunamadı"
        case CardError.pinIncorrect(let retries):
            return retries.map { "PIN hatalı, kalan deneme: \($0)" } ?? "PIN hatalı"
        case CardError.fileNotFound: return "Kart dizini okunamadı"
        case let CardError.apduFailed(sw): return String(format: "Kart komutu başarısız: %04X", sw)
        case let CardError.parse(reason): return reason
        default: return "İşlem başarısız"
        }
    }
}
