import Foundation
import Testing
@testable import SignCore

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("UDF attributed text")
struct UDFAttributedTextTests {
    @Test("document to attributed applies the run font")
    func forward() throws {
        var document = UDFDocument()
        document.text = "abcABC"
        document.styles = [UDFStyle(name: "default", attributes: [])]
        document.elements = [.paragraph(UDFParagraph(
            attributes: [UDFAttribute("resolver", "default")],
            runs: [
                UDFContentRun(startOffset: 0, length: 3, attributes: [UDFAttribute("family", "Helvetica"), UDFAttribute("size", "12")]),
                UDFContentRun(startOffset: 3, length: 3, attributes: [UDFAttribute("family", "Helvetica"), UDFAttribute("size", "12"), UDFAttribute("bold", "true")]),
            ]
        ))]
        let attributed = UDFAttributedText.attributedString(from: document)
        #expect(attributed.string == "abcABC")

        let boldFont = try #require(attributed.attribute(.font, at: 3, effectiveRange: nil) as? UDFFont)
        #expect(fontTraits(boldFont).bold)
        let plainFont = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UDFFont)
        #expect(fontTraits(plainFont).bold == false)
    }

    @Test("attributed to document preserves text and bold run")
    func reverse() throws {
        let plain = NSAttributedString(string: "Normal ", attributes: [.font: makeFont(family: "Helvetica", size: 12, bold: false, italic: false)])
        let bold = NSAttributedString(string: "Kalın", attributes: [.font: makeFont(family: "Helvetica", size: 12, bold: true, italic: false)])
        let composed = NSMutableAttributedString()
        composed.append(plain)
        composed.append(bold)

        let document = UDFAttributedText.document(from: composed)
        #expect(document.text == "Normal Kalın")

        guard case .paragraph(let paragraph) = document.elements.first else {
            Issue.record("paragraf yok"); return
        }
        let boldRun = paragraph.runs.first { $0.attributes.value("bold") == "true" }
        #expect(boldRun != nil)
        #expect(boldRun?.startOffset == 7)
    }

    @Test("attributed round trip keeps the bold range")
    func roundTrip() throws {
        let composed = NSMutableAttributedString()
        composed.append(NSAttributedString(string: "ab", attributes: [.font: makeFont(family: "Helvetica", size: 13, bold: false, italic: false)]))
        composed.append(NSAttributedString(string: "cd", attributes: [.font: makeFont(family: "Helvetica", size: 13, bold: true, italic: false)]))

        let document = UDFAttributedText.document(from: composed)
        let back = UDFAttributedText.attributedString(from: document)
        #expect(back.string == "abcd")
        let boldFont = try #require(back.attribute(.font, at: 2, effectiveRange: nil) as? UDFFont)
        #expect(fontTraits(boldFont).bold)
    }
}
