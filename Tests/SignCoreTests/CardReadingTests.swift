import Foundation
import Testing
@testable import SignCore

@Suite("APDU recipes")
struct ApduRecipesTests {
    @Test("select by file id builds A4 02 0C")
    func selectFileID() {
        let apdu = [UInt8](ApduRecipes.selectFileID(0x5031, expectFCP: false))
        #expect(apdu == [0x00, 0xA4, 0x02, 0x0C, 0x02, 0x50, 0x31])
    }

    @Test("read binary encodes offset and length")
    func readBinary() {
        let apdu = [UInt8](ApduRecipes.readBinary(offset: 0x0100, length: 0x00))
        #expect(apdu == [0x00, 0xB0, 0x01, 0x00, 0x00])
    }

    @Test("verify PIN wraps the code in a 20 command")
    func verifyPIN() {
        let apdu = [UInt8](ApduRecipes.verifyPIN(Data([0x31, 0x32, 0x33, 0x34])))
        #expect(apdu == [0x00, 0x20, 0x00, 0x00, 0x04, 0x31, 0x32, 0x33, 0x34])
    }

    @Test("compute signature requests a response")
    func computeSignature() {
        let apdu = [UInt8](ApduRecipes.computeSignature(Data([0xAA, 0xBB])))
        #expect(apdu == [0x00, 0x2A, 0x9E, 0x9A, 0x02, 0xAA, 0xBB, 0x00])
    }
}

@Suite("Certificate parsing")
struct CertificateInfoTests {
    @Test("extracts TCKN and nonRepudiation")
    func parseEntry() throws {
        let der = try TestCertificateFactory.makeDER(tckn: "12345678901", nonRepudiation: true)
        let entry = try CertificateInfo.entry(fromDER: der)
        #expect(entry.tckn == "12345678901")
        #expect(entry.hasNonRepudiation)
        #expect(entry.certificateId.count == 64)
        #expect(!entry.certificateBase64.isEmpty)
    }

    @Test("no nonRepudiation flag when key usage differs")
    func noNonRepudiation() throws {
        let der = try TestCertificateFactory.makeDER(tckn: "98765432109", nonRepudiation: false)
        let entry = try CertificateInfo.entry(fromDER: der)
        #expect(entry.hasNonRepudiation == false)
    }
}

@Suite("PKCS#15 reader")
struct Pkcs15ReaderTests {
    @Test("extractPaths finds 2-byte octet strings")
    func extractPaths() {
        // SEQUENCE { OCTET STRING C0 00 }
        let der = Data([0x30, 0x04, 0x04, 0x02, 0xC0, 0x00])
        #expect(Pkcs15Reader.extractPaths(fromDER: der) == [0xC000])
    }

    @Test("readEF concatenates chunks across 256-byte reads")
    func readChunks() async throws {
        let content = Data((0..<500).map { UInt8($0 & 0xFF) })
        let session = MockCardSession(files: [0xC000: content])
        let reader = Pkcs15Reader(session: session)
        let read = try await reader.readEF(0xC000)
        #expect(read == content)
    }

    @Test("certificates follows ODF path to a certificate EF")
    func enumerate() async throws {
        let der = try TestCertificateFactory.makeDER(tckn: "12345678901", nonRepudiation: true)
        // ODF points at file 0xC000, which holds the certificate.
        let odf = Data([0x30, 0x04, 0x04, 0x02, 0xC0, 0x00])
        let session = MockCardSession(files: [
            Pkcs15Reader.efODF: odf,
            0xC000: der,
        ])
        let reader = Pkcs15Reader(session: session)
        let found = try await reader.certificates()
        #expect(found.count == 1)
        #expect(found.first == der)
    }
}
