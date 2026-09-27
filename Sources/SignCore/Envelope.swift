import Foundation

/// Response status carried in every API envelope.
public enum ResponseStatus: String, Codable, Sendable {
    case ok = "OK"
    case error = "ERROR"
    case notImplemented = "NOT_IMPLEMENTED"
}

/// Metadata block attached to every response.
public struct ResponseMetadata: Codable, Sendable {
    public let status: ResponseStatus
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case status = "STATUS"
        case message = "MESSAGE"
    }

    public init(status: ResponseStatus, message: String? = nil) {
        self.status = status
        self.message = message
    }
}

/// Generic response envelope: `{ "data": <payload>, "metadata": { ... } }`.
public struct Envelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let data: Payload?
    public let metadata: ResponseMetadata

    public init(data: Payload?, metadata: ResponseMetadata) {
        self.data = data
        self.metadata = metadata
    }

    public static func ok(_ data: Payload, message: String? = nil) -> Envelope<Payload> {
        Envelope(data: data, metadata: ResponseMetadata(status: .ok, message: message))
    }

    public static func failure(_ message: String) -> Envelope<Payload> {
        Envelope(data: nil, metadata: ResponseMetadata(status: .error, message: message))
    }

    public static func notImplemented() -> Envelope<Payload> {
        Envelope(data: nil, metadata: ResponseMetadata(status: .notImplemented, message: nil))
    }
}
