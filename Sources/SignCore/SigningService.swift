import Foundation

/// Card presence state reported over the status stream.
public enum CardStatus: String, Codable, Sendable {
    case absent
    case present
    case reading
    case error
}

/// One card status event for the SSE stream.
public struct CardStatusEvent: Codable, Sendable {
    public let status: CardStatus
    public let readerName: String?
    public let message: String?

    public init(status: CardStatus, readerName: String? = nil, message: String? = nil) {
        self.status = status
        self.readerName = readerName
        self.message = message
    }
}

/// Business interface behind the loopback endpoints.
public protocol SigningService: Sendable {
    func listCertificates() async -> Envelope<[CertificateEntry]>
    func sign(_ request: SignRequest) async -> Envelope<SignResult>
    func cardStatusStream() -> AsyncStream<CardStatusEvent>
}

/// Placeholder service used until the card layer is wired in.
public struct StubSigningService: SigningService {
    public init() {}

    public func listCertificates() async -> Envelope<[CertificateEntry]> {
        .notImplemented()
    }

    public func sign(_ request: SignRequest) async -> Envelope<SignResult> {
        .notImplemented()
    }

    public func cardStatusStream() -> AsyncStream<CardStatusEvent> {
        AsyncStream { continuation in
            continuation.yield(CardStatusEvent(status: .absent, message: "hazır değil"))
            continuation.finish()
        }
    }
}
