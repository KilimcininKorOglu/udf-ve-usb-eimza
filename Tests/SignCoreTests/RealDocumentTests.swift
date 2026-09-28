import Foundation
import Testing

@testable import SignCore

/// Round-trips the real court documents kept in the git-ignored `.udf-samples`
/// directory. The suite skips when that directory is absent (for example on
/// CI), so it never fails a machine that does not hold the private samples.
@Suite("Real UDF documents")
struct RealDocumentTests {
    private func sampleURLs() -> [URL] {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".udf-samples")
        let contents = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        return (contents ?? []).filter { $0.pathExtension == "udf" }.sorted { $0.path < $1.path }
    }

    @Test("every sample round-trips through the editor bridge without losing structure")
    func samplesRoundTrip() throws {
        let urls = sampleURLs()
        try #require(!urls.isEmpty || FileManager.default.fileExists(atPath: ".udf-samples") == false)
        for url in urls {
            try check(url)
        }
    }

    private func check(_ url: URL) throws {
        let name = url.lastPathComponent
        let original: UDFDocument
        do { original = try UDFReader.read(udf: try Data(contentsOf: url)) } catch {
            Issue.record("orijinal okunamadı: \(name): \(error)")
            return
        }
        let attributed = UDFAttributedText.attributedString(from: original)
        let rebuilt = UDFAttributedText.document(from: attributed, template: original)
        let written = try UDFWriter.write(rebuilt)
        let reread: UDFDocument
        do { reread = try UDFReader.read(udf: written) } catch {
            Issue.record("yeniden yazılan bozuk: \(name): \(error)")
            return
        }

        #expect(tableCount(reread) == tableCount(original), "tablo sayısı değişti: \(name)")
        #expect(
            imageCount(reread) == imageCount(original),
            "görsel sayısı değişti: \(name) \(imageCount(original)) -> \(imageCount(reread))")
        #expect(sectionCount(reread) == sectionCount(original), "üst/altbilgi sayısı değişti: \(name)")
    }

    // MARK: Counters

    private func tableCount(_ document: UDFDocument) -> Int {
        document.elements.filter { if case .table = $0 { return true } else { return false } }.count
    }

    private func sectionCount(_ document: UDFDocument) -> Int {
        document.elements.filter {
            switch $0 {
            case .header, .footer: return true
            default: return false
            }
        }.count
    }

    private func imageCount(_ document: UDFDocument) -> Int {
        document.elements.reduce(0) { total, element in
            guard case .paragraph(let paragraph) = element else { return total }
            return total + paragraph.inlines.filter { if case .image = $0 { return true } else { return false } }.count
        }
    }
}
