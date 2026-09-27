import Foundation
import Testing
@testable import SignCore

@Suite("Router dispatch")
struct RouterTests {
    private func request(_ method: String, _ path: String, body: Data = Data(), origin: String? = nil) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let origin { headers["origin"] = origin }
        return HTTPRequest(method: method, path: path, query: [:], headers: headers, body: body)
    }

    private func statusField(_ response: HTTPResponse) throws -> String {
        let json = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let metadata = try #require(json["metadata"] as? [String: Any])
        return try #require(metadata["STATUS"] as? String)
    }

    @Test("getCertificates routes to service, returns NOT_IMPLEMENTED from stub")
    func certificates() async throws {
        let router = Router(service: StubSigningService())
        let outcome = await router.route(request("GET", "/api/v1/signature/getCertificates"))
        guard case .response(let response) = outcome else { Issue.record("beklenen response"); return }
        #expect(try statusField(response) == "NOT_IMPLEMENTED")
    }

    @Test("sign with empty body returns ERROR and 400")
    func signBadBody() async throws {
        let router = Router(service: StubSigningService())
        let outcome = await router.route(request("POST", "/api/v1/signature/sign", body: Data("{}".utf8)))
        guard case .response(let response) = outcome else { Issue.record("beklenen response"); return }
        #expect(response.status == 400)
        #expect(try statusField(response) == "ERROR")
    }

    @Test("OPTIONS preflight reflects origin with 204")
    func preflight() async throws {
        let router = Router(service: StubSigningService())
        let preflightRequest = request("OPTIONS", "/api/v1/signature/sign", origin: "https://www.turkiye.gov.tr")
        let outcome = await router.route(preflightRequest)
        guard case .response(let response) = outcome else { Issue.record("beklenen response"); return }
        #expect(response.status == 204)
        #expect(response.headers["access-control-allow-origin"] == "https://www.turkiye.gov.tr")
    }

    @Test("usb-stream routes to an event stream")
    func stream() async throws {
        let router = Router(service: StubSigningService())
        let outcome = await router.route(request("GET", "/api/v1/usb-stream"))
        guard case .eventStream(let stream) = outcome else { Issue.record("beklenen eventStream"); return }
        var seen: [CardStatus] = []
        for await event in stream { seen.append(event.status) }
        #expect(seen == [.absent])
    }

    @Test("unknown path returns 404 ERROR")
    func unknown() async throws {
        let router = Router(service: StubSigningService())
        let outcome = await router.route(request("GET", "/api/v1/yok"))
        guard case .response(let response) = outcome else { Issue.record("beklenen response"); return }
        #expect(response.status == 404)
    }

    @Test("path parser splits query")
    func pathParser() {
        let (path, query) = HTTPRequestParser.splitPath("/api/v1/usb-stream?id=42&x=a%20b")
        #expect(path == "/api/v1/usb-stream")
        #expect(query["id"] == "42")
        #expect(query["x"] == "a b")
    }
}
