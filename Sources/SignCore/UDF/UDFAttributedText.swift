import Foundation

#if canImport(AppKit)
import AppKit
public typealias UDFFont = NSFont
public typealias UDFColor = NSColor
private typealias UDFFontDescriptor = NSFontDescriptor
#elseif canImport(UIKit)
import UIKit
public typealias UDFFont = UIFont
public typealias UDFColor = UIColor
private typealias UDFFontDescriptor = UIFontDescriptor
#endif

/// Bridges the UDF model and an `NSAttributedString`. UDF offsets are UTF-16
/// based, which matches `NSString` and `NSAttributedString`.
public enum UDFAttributedText {
    /// Builds an attributed string from a document's paragraphs and runs.
    public static func attributedString(from document: UDFDocument) -> NSAttributedString {
        let styleByName = Dictionary(document.styles.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let source = document.text as NSString
        let result = NSMutableAttributedString()

        for element in document.elements {
            guard case .paragraph(let paragraph) = element else { continue }
            let paragraphStyle = paragraph.attributes.value("resolver")
            for run in paragraph.textRuns {
                guard let text = safeSubstring(source, offset: run.startOffset, length: run.length) else { continue }
                let merged = resolvedAttributes(run: run, paragraphStyle: paragraphStyle, styles: styleByName)
                result.append(NSAttributedString(string: text, attributes: merged))
            }
        }
        return result
    }

    /// Rebuilds a document from an edited attributed string, splitting the text
    /// into paragraphs on newlines and grouping runs by equal attributes.
    public static func document(
        from attributed: NSAttributedString,
        formatID: String = "1.7",
        pageFormat: [UDFAttribute] = [],
        defaultStyle: UDFStyle = UDFStyle(name: "default", attributes: [])
    ) -> UDFDocument {
        let fullText = attributed.string
        var elements: [UDFElement] = []
        let nsText = fullText as NSString
        var paragraphRuns: [UDFContentRun] = []

        attributed.enumerateAttributes(in: NSRange(location: 0, length: nsText.length)) { attrs, range, _ in
            let runAttributes = styleAttributes(from: attrs)
            let run = UDFContentRun(startOffset: range.location, length: range.length, attributes: runAttributes)
            paragraphRuns.append(run)
        }
        if !paragraphRuns.isEmpty || nsText.length == 0 {
            elements.append(.paragraph(UDFParagraph(
                attributes: [UDFAttribute("resolver", defaultStyle.name)],
                runs: paragraphRuns
            )))
        }
        return UDFDocument(
            formatID: formatID,
            text: fullText,
            pageFormat: pageFormat,
            styles: [defaultStyle],
            elements: elements
        )
    }

    // MARK: Attribute resolution

    private static func resolvedAttributes(
        run: UDFContentRun,
        paragraphStyle: String?,
        styles: [String: UDFStyle]
    ) -> [NSAttributedString.Key: Any] {
        var merged: [UDFAttribute] = []
        if let name = paragraphStyle, let style = styles[name] { merged += style.attributes }
        if let name = run.attributes.value("resolver"), let style = styles[name] { merged += style.attributes }
        merged += run.attributes
        return textAttributes(from: merged)
    }

    private static func textAttributes(from attributes: [UDFAttribute]) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]
        result[.font] = font(from: attributes)
        if let hex = attributes.value("foreground"), let color = color(fromHex: hex) {
            result[.foregroundColor] = color
        }
        return result
    }

    private static func font(from attributes: [UDFAttribute]) -> UDFFont {
        let family = attributes.value("family") ?? "Helvetica"
        let size = CGFloat(Double(attributes.value("size") ?? "12") ?? 12)
        let bold = attributes.value("bold") == "true"
        let italic = attributes.value("italic") == "true"
        return makeFont(family: family, size: size, bold: bold, italic: italic)
    }

    private static func styleAttributes(from attrs: [NSAttributedString.Key: Any]) -> [UDFAttribute] {
        guard let font = attrs[.font] as? UDFFont else { return [] }
        var out: [UDFAttribute] = [
            UDFAttribute("family", font.familyName ?? "Helvetica"),
            UDFAttribute("size", String(Int(font.pointSize.rounded()))),
        ]
        let traits = fontTraits(font)
        out.append(UDFAttribute("bold", traits.bold ? "true" : "false"))
        out.append(UDFAttribute("italic", traits.italic ? "true" : "false"))
        return out
    }
}
