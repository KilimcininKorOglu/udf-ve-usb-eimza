import Crypto
import Foundation
import Testing

@testable import SignCore

/// A virtual card that serves a certificate over PKCS#15 and answers the
/// signing commands with a placeholder signature. Cryptographic correctness
/// of the output is covered by the builder suites; this exercises the wiring.
final class VirtualCard: CardSession, @unchecked Sendable {
    let files: [UInt16: Data]
    let expectedPIN: String
    private var selected: UInt16?

    init(files: [UInt16: Data], expectedPIN: String) {
        self.files = files
        self.expectedPIN = expectedPIN
    }

    func transmit(_ apdu: Data) async throws -> APDUResponse {
        let bytes = [UInt8](apdu)
        switch bytes[1] {
        case 0xA4:
            if bytes[2] == 0x02 {
                let fid = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])
                guard files[fid] != nil else { return APDUResponse(data: Data(), sw1: 0x6A, sw2: 0x82) }
                selected = fid
            }
            return ok()
        case 0xB0:
            return read(bytes)
        case 0x20:
            let pin = String(decoding: bytes[5...], as: UTF8.self)
            return pin == expectedPIN ? ok() : APDUResponse(data: Data(), sw1: 0x63, sw2: 0xC2)
        case 0x22:
            return ok()
        case 0x2A:
            return APDUResponse(data: Data(repeating: 0xAB, count: 128), sw1: 0x90, sw2: 0x00)
        default:
            return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
        }
    }

    func end() async {}

    private func ok() -> APDUResponse { APDUResponse(data: Data(), sw1: 0x90, sw2: 0x00) }

    private func read(_ bytes: [UInt8]) -> APDUResponse {
        guard let fid = selected, let content = files[fid] else {
            return APDUResponse(data: Data(), sw1: 0x6B, sw2: 0x00)
        }
        let offset = Int(bytes[2]) << 8 | Int(bytes[3])
        guard offset < content.count else { return APDUResponse(data: Data(), sw1: 0x6B, sw2: 0x00) }
        let end = min(offset + 256, content.count)
        return APDUResponse(data: content.subdata(in: offset..<end), sw1: 0x90, sw2: 0x00)
    }
}

struct VirtualCardTransport: CardTransport {
    let card: VirtualCard

    func listSlots() async throws -> [String] { ["Virtual Reader"] }
    func openSession(slotName: String?) async throws -> CardSession { card }
}

@Suite("Card signing service")
struct CardSigningServiceTests {
    private func makeService(pin: String) throws -> (CardSigningService, String) {
        let der = try TestCertificateFactory.makeDER(tckn: "12345678901", nonRepudiation: true)
        let odf = Data([0x30, 0x04, 0x04, 0x02, 0xC0, 0x00])
        let card = VirtualCard(files: [Pkcs15Reader.efODF: odf, 0xC000: der], expectedPIN: pin)
        let certId = Data(SHA256Fingerprint.of(der)).map { String(format: "%02x", $0) }.joined()
        return (CardSigningService(transport: VirtualCardTransport(card: card)), certId)
    }

    @Test("getCertificates returns the card certificate with its TCKN")
    func certificates() async throws {
        let (service, _) = try makeService(pin: "1234")
        let envelope = await service.listCertificates()
        #expect(envelope.metadata.status == .ok)
        #expect(envelope.data?.count == 1)
        #expect(envelope.data?.first?.tckn == "12345678901")
    }

    @Test("sign produces a CAdES envelope for the right PIN")
    func signCAdES() async throws {
        let (service, certId) = try makeService(pin: "1234")
        let request = SignRequest(
            certificateId: certId, password: "1234",
            signatureType: .cades, contentBase64: Data("belge".utf8).base64EncodedString()
        )
        let envelope = await service.sign(request)
        #expect(envelope.metadata.status == .ok)
        let der = try #require(envelope.data.map { Data(base64Encoded: $0.signedDataBase64) } ?? nil)
        #expect(der.first == 0x30)
    }

    @Test("missing credentials rejected")
    func missingCredentials() async throws {
        let (service, certId) = try makeService(pin: "1234")
        let request = SignRequest(certificateId: certId, password: "", signatureType: .cades, contentBase64: "AAAA")
        let envelope = await service.sign(request)
        #expect(envelope.metadata.status == .error)
        #expect(envelope.metadata.message == "certificateId/password gerekli")
    }

    @Test("wrong PIN surfaces a PIN error")
    func wrongPIN() async throws {
        let (service, certId) = try makeService(pin: "1234")
        let request = SignRequest(
            certificateId: certId, password: "0000",
            signatureType: .cades, contentBase64: Data("belge".utf8).base64EncodedString()
        )
        let envelope = await service.sign(request)
        #expect(envelope.metadata.status == .error)
        #expect(envelope.metadata.message?.contains("PIN hatalı") == true)
    }
}

/// Small SHA-256 helper for the test's certificate id.
enum SHA256Fingerprint {
    static func of(_ data: Data) -> [UInt8] {
        Array(Crypto.SHA256.hash(data: data))
    }
}
