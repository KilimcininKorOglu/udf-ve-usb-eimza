import Foundation

/// Outcome of routing a request: either a complete response or an SSE stream.
public enum RouteOutcome: Sendable {
    case response(HTTPResponse)
    case eventStream(AsyncStream<CardStatusEvent>)
}

/// Maps HTTP requests to the signing service and builds the JSON envelope.
public struct Router: Sendable {
    private let service: any SigningService
    private let encoder: JSONEncoder

    public init(service: any SigningService) {
        self.service = service
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func route(_ request: HTTPRequest) async -> RouteOutcome {
        if request.method == "OPTIONS" {
            return .response(preflight(request))
        }
        switch (request.method, request.path) {
        case ("GET", SignBridgeInfo.apiPrefix + "/signature/getCertificates"):
            return .response(await certificatesResponse(request))
        case ("POST", SignBridgeInfo.apiPrefix + "/signature/sign"):
            return .response(await signResponse(request))
        case ("GET", SignBridgeInfo.apiPrefix + "/usb-stream"):
            return .eventStream(service.cardStatusStream())
        default:
            return .response(errorResponse("bilinmeyen endpoint", status: 404, origin: request.header("origin")))
        }
    }

    private func certificatesResponse(_ request: HTTPRequest) async -> HTTPResponse {
        let envelope = await service.listCertificates()
        return encoded(envelope, origin: request.header("origin"))
    }

    private func signResponse(_ request: HTTPRequest) async -> HTTPResponse {
        guard let parsed = try? JSONDecoder().decode(SignRequest.self, from: request.body) else {
            let env = Envelope<SignResult>.failure("certificateId/password gerekli")
            return encoded(env, origin: request.header("origin"), status: 400)
        }
        let envelope = await service.sign(parsed)
        let status = envelope.metadata.status == .ok ? 200 : 400
        return encoded(envelope, origin: request.header("origin"), status: status)
    }

    private func encoded<T: Encodable>(_ value: T, origin: String?, status: Int = 200) -> HTTPResponse {
        guard let body = try? encoder.encode(value) else {
            return errorResponse("kodlama hatası", status: 500, origin: origin)
        }
        var response = HTTPResponse.json(body, status: status)
        applyCORS(&response.headers, origin: origin)
        return response
    }

    private func errorResponse(_ message: String, status: Int, origin: String?) -> HTTPResponse {
        let env = Envelope<[String]>.failure(message)
        let body = (try? encoder.encode(env)) ?? Data("{}".utf8)
        var response = HTTPResponse.json(body, status: status)
        applyCORS(&response.headers, origin: origin)
        return response
    }

    private func preflight(_ request: HTTPRequest) -> HTTPResponse {
        var response = HTTPResponse(status: 204)
        applyCORS(&response.headers, origin: request.header("origin"))
        return response
    }

    private func applyCORS(_ headers: inout [String: String], origin: String?) {
        headers["access-control-allow-origin"] = origin ?? "*"
        headers["access-control-allow-credentials"] = "true"
        headers["access-control-allow-methods"] = "GET, POST, OPTIONS"
        headers["access-control-allow-headers"] = "content-type, authorization"
        headers["vary"] = "Origin"
    }
}
