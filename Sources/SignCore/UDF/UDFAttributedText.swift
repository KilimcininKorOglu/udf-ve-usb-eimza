import Foundation

#if canImport(AppKit)
import AppKit
public typealias UDFFont = NSFont
public typealias UDFColor = NSColor
#elseif canImport(UIKit)
import UIKit
public typealias UDFFont = UIFont
public typealias UDFColor = UIColor
#endif

/// Bridges the UDF model and an `NSAttributedString`. UDF offsets are UTF-16
/// based, which matches `NSString` and `NSAttributedString`. The bridge renders
/// paragraphs (with their runs, inline images and fields) into editable text,
/// carries tables and other block elements as attachments so they keep their
/// order, and keeps the page format, styles, headers and footers as a template
/// that the writer re-applies on save.
public enum UDFAttributedText {
    /// Paragraph attribute names mapped onto `NSParagraphStyle`; every other
    /// paragraph attribute (the `resolver` and any custom one) is carried in the
    /// `udfParagraphMeta` marker so it survives an edit.
    private static let styleAttributeNames: Set<String> = [
        "alignment", "leftIndent", "rightIndent", "firstLineIndent", "lineSpacing",
    ]

    /// Run attributes regenerated from the rendered font and colours on save; a
    /// field marker must not also carry them, or the writer emits each twice.
    private static let runStyleNames: Set<String> = [
        "family", "size", "bold", "italic", "foreground", "background",
        "underline", "strikethrough", "baselineOffset", "resolver",
    ]

    /// The shared rendering inputs for one paragraph's inlines.
    private struct RenderContext {
        let source: NSString
        let style: NSParagraphStyle
        let meta: [UDFAttribute]
        let styles: [String: UDFStyle]
    }

    // MARK: Document to attributed string

    /// Builds an attributed string from a document's body elements. Headers,
    /// footers, the page format and the styles are not part of the flowing text.
    public static func attributedString(from document: UDFDocument) -> NSAttributedString {
        let styleByName = Dictionary(document.styles.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let source = document.text as NSString
        let result = NSMutableAttributedString()
        for element in document.elements {
            appendElement(element, into: result, source: source, styles: styleByName)
        }
        return result
    }

    private static func appendElement(
        _ element: UDFElement,
        into result: NSMutableAttributedString,
        source: NSString,
        styles: [String: UDFStyle]
    ) {
        switch element {
        case .paragraph(let paragraph):
            appendParagraph(paragraph, into: result, source: source, styles: styles)
        case .header, .footer:
            break  // Page furniture; edited through the page panel, not the body.
        default:
            result.append(blockAttachment(for: element, source: source))
        }
    }

    private static func appendParagraph(
        _ paragraph: UDFParagraph,
        into result: NSMutableAttributedString,
        source: NSString,
        styles: [String: UDFStyle]
    ) {
        let style = paragraphStyle(from: paragraph.attributes)
        let meta = paragraph.attributes.filter { !styleAttributeNames.contains($0.name) }
        let context = RenderContext(source: source, style: style, meta: meta, styles: styles)
        for inline in paragraph.inlines {
            appendInline(inline, into: result, context: context)
        }
        let newline = NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .udfParagraphMeta: meta])
        result.append(newline)
    }

    private static func appendInline(
        _ inline: UDFInline,
        into result: NSMutableAttributedString,
        context: RenderContext
    ) {
        switch inline {
        case .content(let run), .space(let run):
            appendRun(run, field: nil, into: result, context: context)
        case .field(let run):
            appendRun(run, field: run.attributes, into: result, context: context)
        case .image(let raw):
            if let image = inlineImageAttachment(raw) { result.append(image) }
        case .raw(let raw):
            result.append(blockAttachment(for: .raw(raw), source: context.source))
        }
    }

    private static func appendRun(
        _ run: UDFContentRun,
        field: [UDFAttribute]?,
        into result: NSMutableAttributedString,
        context: RenderContext
    ) {
        guard let text = safeSubstring(context.source, offset: run.startOffset, length: run.length),
            !text.isEmpty
        else { return }
        var attributes = textAttributes(from: resolvedAttributes(run: run, styles: context.styles))
        attributes[.paragraphStyle] = context.style
        attributes[.udfParagraphMeta] = context.meta
        if let field { attributes[.udfField] = field.filter { !runStyleNames.contains($0.name) } }
        result.append(NSAttributedString(string: text, attributes: attributes))
    }

    private static func resolvedAttributes(run: UDFContentRun, styles: [String: UDFStyle]) -> [UDFAttribute] {
        var merged: [UDFAttribute] = []
        if let name = run.attributes.value("resolver"), let style = styles[name] { merged += style.attributes }
        merged += run.attributes
        return merged
    }

    // MARK: Attributed string to document

    /// Rebuilds a document from an edited attributed string, re-applying the
    /// template's page format, styles, headers and footers.
    public static func document(
        from attributed: NSAttributedString,
        template: UDFDocument = UDFDocument()
    ) -> UDFDocument {
        let builder = BodyBuilder()
        let full = attributed.length
        attributed.enumerateAttributes(in: NSRange(location: 0, length: full)) { attrs, range, _ in
            consume(attributed, attrs: attrs, range: range, into: builder)
        }
        let body = builder.finish()
        let merged = mergeSidecar(body: body, template: template)
        var text = ""
        let elements = UDFTextReflow.flatten(merged, source: template.text as NSString, into: &text)
        return UDFDocument(
            formatID: template.formatID,
            text: text,
            pageFormat: template.pageFormat,
            styles: template.styles.isEmpty ? [UDFStyle(name: "default", attributes: [])] : template.styles,
            elements: elements
        )
    }

    private static func consume(
        _ attributed: NSAttributedString,
        attrs: [NSAttributedString.Key: Any],
        range: NSRange,
        into builder: BodyBuilder
    ) {
        if let block = attrs[.attachment] as? UDFElementAttachment {
            builder.addBlock(block.element)
            return
        }
        if let attachment = attrs[.attachment] as? NSTextAttachment {
            builder.addImage(rawImage(from: attachment))
            return
        }
        let text = (attributed.string as NSString).substring(with: range)
        builder.addText(
            text,
            style: styleAttributes(from: attrs),
            paragraph: paragraphAttributes(from: attrs),
            field: attrs[.udfField] as? [UDFAttribute]
        )
    }

    private static func mergeSidecar(body: [UDFElement], template: UDFDocument) -> [UDFElement] {
        var result = body
        for (index, element) in template.elements.enumerated() {
            switch element {
            case .header, .footer:
                result.insert(element, at: min(index, result.count))
            default:
                break
            }
        }
        return result
    }

}

extension UDFAttributedText {
    // MARK: Attribute mapping

    private static func textAttributes(from attributes: [UDFAttribute]) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [.font: font(from: attributes)]
        if let hex = attributes.value("foreground"), let color = color(fromHex: hex) {
            result[.foregroundColor] = color
        }
        if let hex = attributes.value("background"), let color = color(fromHex: hex) {
            result[.backgroundColor] = color
        }
        if attributes.value("underline") == "true" { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if attributes.value("strikethrough") == "true" {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let raw = attributes.value("baselineOffset"), let value = Double(raw) {
            result[.baselineOffset] = CGFloat(value)
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
        let traits = fontTraits(font)
        var out: [UDFAttribute] = [
            UDFAttribute("family", font.familyName ?? "Helvetica"),
            UDFAttribute("size", String(Int(font.pointSize.rounded()))),
            UDFAttribute("bold", traits.bold ? "true" : "false"),
            UDFAttribute("italic", traits.italic ? "true" : "false"),
        ]
        if let color = attrs[.foregroundColor] as? UDFColor {
            out.append(UDFAttribute("foreground", udfColorString(color)))
        }
        if let color = attrs[.backgroundColor] as? UDFColor {
            out.append(UDFAttribute("background", udfColorString(color)))
        }
        if (attrs[.underlineStyle] as? Int ?? 0) != 0 { out.append(UDFAttribute("underline", "true")) }
        if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { out.append(UDFAttribute("strikethrough", "true")) }
        if let offset = attrs[.baselineOffset] as? CGFloat, offset != 0 {
            out.append(UDFAttribute("baselineOffset", String(Int(offset.rounded()))))
        }
        return out
    }

    // MARK: Paragraph mapping

    private static func paragraphStyle(from attributes: [UDFAttribute]) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if let raw = attributes.value("alignment"), let value = Int(raw) { style.alignment = alignment(fromUDF: value) }
        if let value = doubleValue(attributes, "leftIndent") { style.headIndent = value }
        if let value = doubleValue(attributes, "firstLineIndent") { style.firstLineHeadIndent = value }
        if let value = doubleValue(attributes, "rightIndent") { style.tailIndent = -value }
        if let value = doubleValue(attributes, "lineSpacing") { style.lineSpacing = value }
        return style
    }

    private static func paragraphAttributes(from attrs: [NSAttributedString.Key: Any]) -> [UDFAttribute] {
        var out = attrs[.udfParagraphMeta] as? [UDFAttribute] ?? []
        guard let style = attrs[.paragraphStyle] as? NSParagraphStyle else { return out }
        out.append(UDFAttribute("alignment", String(udfAlignment(from: style.alignment))))
        if style.headIndent > 0 { out.append(UDFAttribute("leftIndent", String(Int(style.headIndent)))) }
        if style.firstLineHeadIndent > 0 {
            out.append(UDFAttribute("firstLineIndent", String(Int(style.firstLineHeadIndent))))
        }
        if style.tailIndent < 0 { out.append(UDFAttribute("rightIndent", String(Int(-style.tailIndent)))) }
        if style.lineSpacing > 0 { out.append(UDFAttribute("lineSpacing", String(Int(style.lineSpacing)))) }
        return out
    }

    private static func doubleValue(_ attributes: [UDFAttribute], _ name: String) -> CGFloat? {
        guard let raw = attributes.value(name), let value = Double(raw) else { return nil }
        return CGFloat(value)
    }

    private static func alignment(fromUDF value: Int) -> NSTextAlignment {
        switch value {
        case 1: return .center
        case 2: return .right
        case 3: return .justified
        default: return .left
        }
    }

    private static func udfAlignment(from alignment: NSTextAlignment) -> Int {
        switch alignment {
        case .center: return 1
        case .right: return 2
        case .justified: return 3
        default: return 0
        }
    }

    // MARK: Attachments

    private static func blockAttachment(for element: UDFElement, source: NSString) -> NSAttributedString {
        NSAttributedString(attachment: UDFElementAttachment(element: element, source: source))
    }

    private static func inlineImageAttachment(_ raw: UDFRawElement) -> NSAttributedString? {
        guard let base64 = raw.attributes.value("imageData"),
            let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
            let image = platformImage(from: data)
        else { return nil }
        let attachment = NSTextAttachment()
        setAttachmentImage(attachment, image)
        if let width = doubleValue(raw.attributes, "width"), let height = doubleValue(raw.attributes, "height") {
            attachment.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        }
        return NSAttributedString(attachment: attachment)
    }

    private static func rawImage(from attachment: NSTextAttachment) -> UDFRawElement {
        guard let data = attachmentPNGData(attachment) else {
            return UDFRawElement(name: "image")
        }
        var attributes = [UDFAttribute("imageData", data.base64EncodedString())]
        let bounds = attachment.bounds
        if bounds.width > 0, bounds.height > 0 {
            attributes.append(UDFAttribute("width", String(Int(bounds.width.rounded()))))
            attributes.append(UDFAttribute("height", String(Int(bounds.height.rounded()))))
        }
        return UDFRawElement(name: "image", attributes: attributes)
    }
}

/// Accumulates body elements while walking an edited attributed string. It
/// flushes a paragraph on every newline or block element and stores each run's
/// literal text in the `_text` attribute; the reflow pass assigns the offsets.
private final class BodyBuilder {
    private var elements: [UDFElement] = []
    private var inlines: [UDFInline] = []
    private var paragraphAttributes: [UDFAttribute] = []
    private var hasContent = false

    func addText(_ text: String, style: [UDFAttribute], paragraph: [UDFAttribute], field: [UDFAttribute]?) {
        let segments = text.components(separatedBy: "\n")
        for (index, segment) in segments.enumerated() {
            if index > 0 { emitParagraph(force: true) }
            if !segment.isEmpty { appendContent(segment, style: style, paragraph: paragraph, field: field) }
        }
    }

    func addImage(_ raw: UDFRawElement) {
        hasContent = true
        inlines.append(.image(raw))
    }

    func addBlock(_ element: UDFElement) {
        emitParagraph(force: false)
        elements.append(element)
    }

    /// Emits a trailing paragraph only if it holds content, or if the document
    /// would otherwise be empty; a trailing newline leaves no content.
    func finish() -> [UDFElement] {
        emitParagraph(force: elements.isEmpty)
        return elements
    }

    private func appendContent(
        _ text: String,
        style: [UDFAttribute],
        paragraph: [UDFAttribute],
        field: [UDFAttribute]?
    ) {
        if !hasContent { paragraphAttributes = paragraph }
        hasContent = true
        let carried = style + [UDFAttribute(UDFTextReflow.textKey, text)]
        if let field {
            inlines.append(.field(UDFContentRun(startOffset: 0, length: 0, attributes: carried + field)))
        } else {
            inlines.append(.content(UDFContentRun(startOffset: 0, length: 0, attributes: carried)))
        }
    }

    private func emitParagraph(force: Bool) {
        if hasContent || force {
            elements.append(.paragraph(UDFParagraph(attributes: paragraphAttributes, inlines: inlines)))
        }
        inlines = []
        paragraphAttributes = []
        hasContent = false
    }
}
