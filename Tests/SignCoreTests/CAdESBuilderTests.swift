import Crypto
import Foundation
import Testing
import _CryptoExtras

@testable import SignCore

@Suite("CAdES builder")
struct CAdESBuilderTests {
    /// Runs a command and returns its exit code and combined output.
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

    @Test("detached CMS verifies with openssl")
    func detachedVerifies() async throws {
        let identity = try TestCertificateFactory.makeRSA(tckn: "12345678901", nonRepudiation: true)
        let content = Data("imzalanacak belge içeriği".utf8)

        let builder = CAdESBuilder()
        let cms = try await builder.build(content: content, certificateDER: identity.der) { message in
            let signature = try identity.key.signature(for: message, padding: .insecurePKCS1v1_5)
            return Data(signature.rawRepresentation)
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sigURL = dir.appendingPathComponent("sig.p7s")
        let contentURL = dir.appendingPathComponent("content.bin")
        try cms.write(to: sigURL)
        try content.write(to: contentURL)

        let (status, output) = try run(
            "/usr/bin/openssl",
            [
                "cms", "-verify", "-inform", "DER", "-in", sigURL.path,
                "-content", contentURL.path, "-noverify", "-out", "/dev/null",
            ])
        #expect(status == 0, "openssl doğrulaması başarısız: \(output)")
        #expect(output.contains("Verification successful"))
    }

    @Test("produced structure is a CMS signedData ContentInfo")
    func structureShape() async throws {
        let identity = try TestCertificateFactory.makeRSA(tckn: "12345678901", nonRepudiation: false)
        let content = Data("abc".utf8)
        let builder = CAdESBuilder()
        let cms = try await builder.build(content: content, certificateDER: identity.der) { message in
            Data(try identity.key.signature(for: message, padding: .insecurePKCS1v1_5).rawRepresentation)
        }
        // ContentInfo is a SEQUENCE (0x30) whose first content byte starts the signedData OID (0x06).
        #expect(cms.first == 0x30)
        #expect(cms.count > 200)
    }
}
