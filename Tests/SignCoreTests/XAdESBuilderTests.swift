import Crypto
import Foundation
import Testing
import _CryptoExtras

@testable import SignCore

@Suite("XAdES builder")
struct XAdESBuilderTests {
    private func run(_ launchPath: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test("enveloping XAdES verifies with xmlsec1")
    func envelopingVerifies() async throws {
        let identity = try TestCertificateFactory.makeRSA(tckn: "12345678901", nonRepudiation: true)
        let content = Data("imzalanacak XML belge".utf8)

        let builder = XAdESBuilder()
        let xml = try await builder.build(content: content, certificateDER: identity.der) { message in
            Data(try identity.key.signature(for: message, padding: .insecurePKCS1v1_5).rawRepresentation)
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let xmlURL = dir.appendingPathComponent("sig.xml")
        try xml.write(to: xmlURL)

        let candidates = ["/opt/homebrew/bin/xmlsec1", "/usr/local/bin/xmlsec1", "/usr/bin/xmlsec1"]
        guard let xmlsec = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return  // xmlsec1 is not installed here; the CI job installs it and runs this check.
        }
        let (status, output) = try run(
            xmlsec,
            [
                "--verify", "--insecure",
                "--id-attr:Id", "http://www.w3.org/2000/09/xmldsig#:Object",
                "--id-attr:Id", "http://uri.etsi.org/01903/v1.3.2#:SignedProperties",
                xmlURL.path,
            ])
        #expect(status == 0, "xmlsec1 doğrulaması başarısız: \(output)")
        #expect(output.contains("OK"))
    }

    @Test("serial number renders as decimal")
    func serialDecimal() {
        #expect(decimalString([0x01, 0x00]) == "256")
        #expect(decimalString([0xFF]) == "255")
        #expect(decimalString([0x00]) == "0")
    }
}
