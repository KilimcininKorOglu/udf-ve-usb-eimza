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
///
/// The `data` key is always emitted, as explicit `null` when there is no
/// payload, to match the wire contract consumed by the web clients.
public struct Envelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let data: Payload?
    public let metadata: ResponseMetadata

    enum CodingKeys: String, CodingKey {
        case data
        case metadata
    }

    public init(data: Payload?, metadata: ResponseMetadata) {
        self.data = data
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decodeIfPresent(Payload.self, forKey: .data)
        self.metadata = try container.decode(ResponseMetadata.self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let data {
            try container.encode(data, forKey: .data)
        } else {
            try container.encodeNil(forKey: .data)
        }
        try container.encode(metadata, forKey: .metadata)
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
