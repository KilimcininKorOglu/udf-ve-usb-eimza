import Foundation
import Testing
@testable import SignCore

@Suite("UDF read and write")
struct UDFRoundTripTests {
    private func sampleData() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "sample", withExtension: "udf"))
        return try Data(contentsOf: url)
    }

    @Test("reads the sample document structure")
    func readSample() throws {
        let document = try UDFReader.read(udf: sampleData())
        #expect(document.formatID == "1.7")
        #expect(document.styles.contains { $0.name == "default" })
        #expect(document.styles.contains { $0.name == "hvl-default" })
        #expect(document.pageFormat.value("paperOrientation") == "1")

        guard case .paragraph(let paragraph)? = document.elements.first else {
            Issue.record("ilk eleman paragraf değil"); return
        }
        #expect(paragraph.attributes.value("resolver") == "hvl-default")
        #expect(paragraph.runs.first?.length == 1)
    }

    @Test("read, write and read again yields the same model")
    func roundTrip() throws {
        let document = try UDFReader.read(udf: sampleData())
        let rewritten = try UDFWriter.write(document)
        let reparsed = try UDFReader.read(udf: rewritten)
        #expect(document == reparsed)
    }

    @Test("content XML preserves the document text")
    func textPreserved() throws {
        var document = UDFDocument()
        document.text = "Merhaba dünya"
        document.styles = [UDFStyle(name: "default", attributes: [UDFAttribute("family", "Times New Roman")])]
        document.elements = [.paragraph(UDFParagraph(
            attributes: [UDFAttribute("resolver", "default")],
            runs: [UDFContentRun(startOffset: 0, length: 13)]
        ))]
        let data = try UDFWriter.write(document)
        let reparsed = try UDFReader.read(udf: data)
        #expect(reparsed.text == "Merhaba dünya")
        #expect(reparsed == document)
    }
}
