import Foundation
import Testing

@testable import SignCore

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("UDF attributed-text bridge")
struct UDFAttributedTextTests {
    /// Renders a document to an attributed string and rebuilds it, re-applying
    /// the source document as the template so the page furniture survives.
    private func roundTrip(_ document: UDFDocument) -> UDFDocument {
        let attributed = UDFAttributedText.attributedString(from: document)
        return UDFAttributedText.document(from: attributed, template: document)
    }

    private func firstParagraph(_ document: UDFDocument) -> UDFParagraph? {
        for element in document.elements {
            if case .paragraph(let paragraph) = element { return paragraph }
        }
        return nil
    }

    @Test("run styling and paragraph alignment survive a round trip")
    func stylingSurvives() throws {
        let run = UDFContentRun(
            startOffset: 0,
            length: 7,
            attributes: [
                UDFAttribute("family", "Helvetica"),
                UDFAttribute("size", "14"),
                UDFAttribute("bold", "true"),
                UDFAttribute("underline", "true"),
                UDFAttribute("foreground", "#FF0000"),
                UDFAttribute("baselineOffset", "5"),
            ]
        )
        let paragraph = UDFParagraph(attributes: [UDFAttribute("alignment", "2")], runs: [run])
        let document = UDFDocument(
            text: "Merhaba", styles: [UDFStyle(name: "default", attributes: [])], elements: [.paragraph(paragraph)])

        let rebuilt = roundTrip(document)
        #expect(rebuilt.text == "Merhaba")
        let result = try #require(firstParagraph(rebuilt))
        #expect(result.attributes.value("alignment") == "2")
        let rebuiltRun = try #require(result.textRuns.first)
        #expect(rebuiltRun.attributes.value("bold") == "true")
        #expect(rebuiltRun.attributes.value("underline") == "true")
        #expect(rebuiltRun.attributes.value("family") == "Helvetica")
        #expect(rebuiltRun.attributes.value("baselineOffset") == "5")
        let hex = try #require(rebuiltRun.attributes.value("foreground"))
        let parsed = try #require(color(fromHex: hex))
        let rgb = components(parsed)
        #expect(rgb.red > 0.9)
        #expect(rgb.green < 0.1)
    }

    @Test("an inline image survives a round trip")
    func inlineImageSurvives() throws {
        let base64 = try #require(onePixelPNGBase64())
        let image = UDFRawElement(
            name: "image",
            attributes: [
                UDFAttribute("imageData", base64),
                UDFAttribute("width", "100"),
                UDFAttribute("height", "50"),
            ]
        )
        let paragraph = UDFParagraph(attributes: [], inlines: [.image(image)])
        let document = UDFDocument(text: "", elements: [.paragraph(paragraph)])

        let rebuilt = roundTrip(document)
        let result = try #require(firstParagraph(rebuilt))
        let inlineImage = result.inlines.compactMap { inline -> UDFRawElement? in
            if case .image(let raw) = inline { return raw }
            return nil
        }.first
        let raw = try #require(inlineImage)
        let data = try #require(raw.attributes.value("imageData").flatMap { Data(base64Encoded: $0) })
        #expect(!data.isEmpty)
        #expect(raw.attributes.value("width") == "100")
        #expect(raw.attributes.value("height") == "50")
    }

    @Test("a table keeps its content and position as a block")
    func tableSurvives() throws {
        let cell = UDFCell(elements: [.paragraph(UDFParagraph(runs: []))])
        let table = UDFTable(attributes: [UDFAttribute("border", "1")], rows: [UDFRow(cells: [cell, cell])])
        let before = UDFParagraph(attributes: [], runs: [UDFContentRun(startOffset: 0, length: 3, attributes: [])])
        let document = UDFDocument(text: "üst", elements: [.paragraph(before), .table(table)])

        let rebuilt = roundTrip(document)
        let tables = rebuilt.elements.compactMap { element -> UDFTable? in
            if case .table(let value) = element { return value }
            return nil
        }
        let rebuiltTable = try #require(tables.first)
        #expect(rebuiltTable == table)
        #expect(rebuilt.elements.count == 2)
        if case .paragraph = rebuilt.elements[0] {} else { Issue.record("ilk element paragraf değil") }
        if case .table = rebuilt.elements[1] {} else { Issue.record("ikinci element tablo değil") }
    }

    @Test("table cell text keeps its characters after the offsets are reflowed")
    func tableCellTextSurvives() throws {
        let cellRun = UDFContentRun(startOffset: 1, length: 1, attributes: [])
        let cell = UDFCell(elements: [.paragraph(UDFParagraph(runs: [cellRun]))])
        let table = UDFTable(rows: [UDFRow(cells: [cell])])
        let body = UDFParagraph(runs: [UDFContentRun(startOffset: 0, length: 1, attributes: [])])
        let document = UDFDocument(text: "AB", elements: [.paragraph(body), .table(table)])

        let rebuilt = roundTrip(document)
        let rebuiltTable = try #require(
            rebuilt.elements.compactMap { element -> UDFTable? in
                if case .table(let value) = element { return value }
                return nil
            }.first)
        let rebuiltCellRun = try #require(firstCellRun(rebuiltTable))
        let text = rebuilt.text as NSString
        let range = NSRange(location: rebuiltCellRun.startOffset, length: rebuiltCellRun.length)
        #expect(range.location + range.length <= text.length)
        #expect(text.substring(with: range) == "B")
    }

    private func firstCellRun(_ table: UDFTable) -> UDFContentRun? {
        guard case .paragraph(let paragraph)? = table.rows.first?.cells.first?.elements.first else { return nil }
        return paragraph.textRuns.first
    }

    @Test("a dynamic field round-trips with its field name")
    func fieldSurvives() throws {
        let run = UDFContentRun(startOffset: 0, length: 3, attributes: [UDFAttribute("fieldName", "getIl")])
        let paragraph = UDFParagraph(attributes: [], inlines: [.field(run)])
        let document = UDFDocument(text: "İst", elements: [.paragraph(paragraph)])

        let rebuilt = roundTrip(document)
        let result = try #require(firstParagraph(rebuilt))
        let field = result.inlines.compactMap { inline -> UDFContentRun? in
            if case .field(let value) = inline { return value }
            return nil
        }.first
        let rebuiltField = try #require(field)
        #expect(rebuiltField.attributes.value("fieldName") == "getIl")
        let text = rebuilt.text as NSString
        let range = NSRange(location: rebuiltField.startOffset, length: rebuiltField.length)
        #expect(text.substring(with: range) == "İst")
    }

    @Test("page format, styles, and headers are preserved from the template")
    func templateFurniturePreserved() throws {
        let pageFormat = [UDFAttribute("mediaSizeName", "A4"), UDFAttribute("leftMargin", "72")]
        let styles = [
            UDFStyle(name: "default", attributes: []),
            UDFStyle(name: "hvl-default", attributes: [UDFAttribute("size", "12")]),
        ]
        let header = UDFSection(
            attributes: [UDFAttribute("startPage", "1")], elements: [.paragraph(UDFParagraph(runs: []))])
        let body = UDFParagraph(attributes: [], runs: [UDFContentRun(startOffset: 0, length: 5, attributes: [])])
        let document = UDFDocument(
            text: "gövde", pageFormat: pageFormat, styles: styles, elements: [.paragraph(body), .header(header)])

        let rebuilt = roundTrip(document)
        #expect(rebuilt.pageFormat == pageFormat)
        #expect(rebuilt.styles == styles)
        let headers = rebuilt.elements.compactMap { element -> UDFSection? in
            if case .header(let section) = element { return section }
            return nil
        }
        #expect(headers.first == header)
    }

    @Test("a built header section keeps its text through a save")
    func headerTextSurvives() throws {
        let header = UDFAttributedText.makeSection(text: "Mahkeme", keeping: [UDFAttribute("startPage", "1")])
        let body = UDFParagraph(runs: [UDFContentRun(startOffset: 0, length: 1, attributes: [])])
        let document = UDFDocument(text: "X", elements: [.paragraph(body), .header(header)])

        let rebuilt = roundTrip(document)
        let rebuiltHeader = rebuilt.elements.compactMap { element -> UDFSection? in
            if case .header(let section) = element { return section }
            return nil
        }.first
        let section = try #require(rebuiltHeader)
        #expect(UDFAttributedText.sectionText(section, source: rebuilt.text) == "Mahkeme")
    }

    @Test("an empty document yields a single paragraph")
    func emptyDocument() {
        let rebuilt = roundTrip(UDFDocument())
        #expect(rebuilt.elements.count == 1)
        #expect(rebuilt.text.isEmpty)
    }

    // MARK: Helpers

    private struct RGB {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
    }

    private func components(_ color: UDFColor) -> RGB {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if canImport(AppKit)
        (color.usingColorSpace(.sRGB) ?? color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #elseif canImport(UIKit)
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return RGB(red: red, green: green, blue: blue)
    }

    private func onePixelPNGBase64() -> String? {
        #if canImport(AppKit)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return png.base64EncodedString()
        #elseif canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.pngData()?.base64EncodedString()
        #endif
    }
}
