import Foundation
import Testing

@testable import SignCore

/// Scriptable card for the signing flow. Verifies a known PIN and replays a
/// programmed PSO signature, optionally split behind a 61xx status.
final class MockSignerSession: CardSession, @unchecked Sendable {
    let expectedPIN: String
    let signature: Data
    let splitAfter: Int?
    private(set) var commands: [[UInt8]] = []

    init(expectedPIN: String, signature: Data, splitAfter: Int? = nil) {
        self.expectedPIN = expectedPIN
        self.signature = signature
        self.splitAfter = splitAfter
    }

    func transmit(_ apdu: Data) async throws -> APDUResponse {
        let bytes = [UInt8](apdu)
        commands.append(bytes)
        switch bytes[1] {
        case 0x20: return verify(bytes)
        case 0x22: return APDUResponse(data: Data(), sw1: 0x90, sw2: 0x00)
        case 0x2A: return performSignature()
        case 0xC0: return getResponse()
        default: return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
        }
    }

    func end() async {}

    private func verify(_ bytes: [UInt8]) -> APDUResponse {
        let pin = String(decoding: bytes[5...], as: UTF8.self)
        if pin == expectedPIN { return APDUResponse(data: Data(), sw1: 0x90, sw2: 0x00) }
        return APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2)
    }

    private func performSignature() -> APDUResponse {
        guard let split = splitAfter else {
            return APDUResponse(data: signature, sw1: 0x90, sw2: 0x00)
        }
        let head = signature.prefix(split)
        return APDUResponse(data: Data(head), sw1: 0x61, sw2: UInt8(signature.count - split))
    }

    private func getResponse() -> APDUResponse {
        let split = splitAfter ?? 0
        return APDUResponse(data: Data(signature.suffix(from: split)), sw1: 0x90, sw2: 0x00)
    }
}

@Suite("Card signer")
struct CardSignerTests {
    private let digest = Data((0..<32).map { UInt8($0) })

    @Test("correct PIN verifies")
    func verifyOK() async throws {
        let session = MockSignerSession(expectedPIN: "1234", signature: Data([0xAB]))
        let signer = CardSigner(session: session)
        try await signer.verifyPIN("1234")
    }

    @Test("wrong PIN reports remaining retries")
    func verifyWrong() async {
        let session = MockSignerSession(expectedPIN: "1234", signature: Data([0xAB]))
        let signer = CardSigner(session: session)
        await #expect(throws: CardError.pinIncorrect(retriesLeft: 2)) {
            try await signer.verifyPIN("0000")
        }
    }

    @Test("sign returns the card signature in one response")
    func signWhole() async throws {
        let sig = Data((0..<128).map { UInt8($0 & 0xFF) })
        let session = MockSignerSession(expectedPIN: "1234", signature: sig)
        let signer = CardSigner(session: session)
        let out = try await signer.signSHA256(digest: digest, keyReference: 0x01)
        #expect(out == sig)
    }

    @Test("sign reassembles signature split behind 61xx")
    func signSplit() async throws {
        let sig = Data((0..<48).map { UInt8($0) })
        let session = MockSignerSession(expectedPIN: "1234", signature: sig, splitAfter: 32)
        let signer = CardSigner(session: session)
        let out = try await signer.signSHA256(digest: digest, keyReference: 0x01)
        #expect(out == sig)
    }

    @Test("digest info wraps hash with SHA-256 prefix")
    func digestInfo() {
        let info = [UInt8](DigestInfo.sha256(digest))
        #expect(info.count == 51)
        #expect(Array(info.prefix(2)) == [0x30, 0x31])
        #expect(Array(info.suffix(32)) == Array(digest))
    }
}
