import Foundation
import Testing
@testable import SignCore

@Suite("Envelope JSON contract")
struct EnvelopeTests {
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("OK envelope carries data and STATUS OK")
    func okEnvelope() throws {
        let env = Envelope<[String]>.ok(["a", "b"], message: "tamam")
        let json = try encode(env)
        let metadata = try #require(json["metadata"] as? [String: Any])
        #expect(metadata["STATUS"] as? String == "OK")
        #expect(metadata["MESSAGE"] as? String == "tamam")
        #expect(json["data"] as? [String] == ["a", "b"])
    }

    @Test("error envelope drops data and carries message")
    func errorEnvelope() throws {
        let env = Envelope<[String]>.failure("certificateId/password gerekli")
        let json = try encode(env)
        let metadata = try #require(json["metadata"] as? [String: Any])
        #expect(metadata["STATUS"] as? String == "ERROR")
        #expect(metadata["MESSAGE"] as? String == "certificateId/password gerekli")
        #expect(json["data"] is NSNull)
    }

    @Test("not implemented envelope has no message")
    func notImplementedEnvelope() throws {
        let env = Envelope<[String]>.notImplemented()
        let json = try encode(env)
        let metadata = try #require(json["metadata"] as? [String: Any])
        #expect(metadata["STATUS"] as? String == "NOT_IMPLEMENTED")
        #expect(metadata["MESSAGE"] == nil)
    }

    @Test("sign request decodes required fields")
    func signRequestDecode() throws {
        let body = """
        {"certificateId":"c1","password":"1234","signatureType":"CAdES","contentBase64":"AAAA"}
        """
        let req = try JSONDecoder().decode(SignRequest.self, from: Data(body.utf8))
        #expect(req.certificateId == "c1")
        #expect(req.signatureType == .cades)
    }
}
