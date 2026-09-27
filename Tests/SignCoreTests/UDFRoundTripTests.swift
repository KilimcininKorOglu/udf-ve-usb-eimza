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
        #expect(paragraph.textRuns.first?.length == 1)
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

    @Test("table, image and field elements round-trip")
    func structuralElements() throws {
        var document = UDFDocument()
        document.text = "AB"
        document.styles = [UDFStyle(name: "default", attributes: [])]
        document.elements = [
            .table(UDFTable(attributes: [UDFAttribute("tableName", "t1")], rows: [
                UDFRow(attributes: [], cells: [
                    UDFCell(attributes: [UDFAttribute("columnSpan", "1")], elements: [
                        .paragraph(UDFParagraph(attributes: [UDFAttribute("resolver", "default")],
                                                runs: [UDFContentRun(startOffset: 0, length: 1)])),
                    ]),
                ]),
            ])),
            .image(UDFImage(attributes: [UDFAttribute("imageData", "AAAA")])),
            .field(UDFField(attributes: [UDFAttribute("fieldType", "date")],
                            runs: [UDFContentRun(startOffset: 1, length: 1)])),
        ]
        let reparsed = try UDFReader.read(udf: try UDFWriter.write(document))
        #expect(reparsed == document)
    }

    @Test("inline field, space and image inside a paragraph round-trip in order")
    func inlineParagraphItems() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <template format_id="1.7" >
        <content><![CDATA[ABCDE]]></content><properties><pageFormat mediaSizeName="1" /></properties>\
        <styles><style name="default" /></styles>
        <elements >
        <paragraph resolver="default">\
        <content startOffset="0" length="1" />\
        <field fieldName="getIl" startOffset="1" length="1" />\
        <space startOffset="2" length="1" />\
        <image imageData="AAAA" startOffset="3" length="1" />\
        <content startOffset="4" length="1" />\
        </paragraph>
        </elements>
        </template>
        """
        let document = try UDFReader.parse(contentXML: Data(xml.utf8))
        guard case .paragraph(let paragraph)? = document.elements.first else {
            Issue.record("ilk eleman paragraf değil"); return
        }
        #expect(paragraph.inlines.count == 5)
        guard case .field(let field) = paragraph.inlines[1] else {
            Issue.record("ikinci inline field değil"); return
        }
        #expect(field.attributes.value("fieldName") == "getIl")
        guard case .image = paragraph.inlines[3] else {
            Issue.record("dördüncü inline image değil"); return
        }

        let reparsed = try UDFReader.read(udf: try UDFWriter.write(document))
        #expect(reparsed == document)
    }

    @Test("an unrecognised element is preserved verbatim")
    func rawElementPreserved() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <template format_id="1.7" >
        <content><![CDATA[X]]></content><properties><pageFormat mediaSizeName="1" /></properties>\
        <styles><style name="default" /></styles>
        <elements >
        <header resolver="default"><content startOffset="0" length="1" /></header>
        <paragraph resolver="default"><content startOffset="0" length="1" /></paragraph>
        </elements>
        </template>
        """
        let document = try UDFReader.parse(contentXML: Data(xml.utf8))
        guard case .raw(let header)? = document.elements.first else {
            Issue.record("ilk eleman raw header değil"); return
        }
        #expect(header.name == "header")
        #expect(header.attributes.value("resolver") == "default")
        #expect(header.children.first?.name == "content")

        let reparsed = try UDFReader.read(udf: try UDFWriter.write(document))
        #expect(reparsed == document)
    }
}
