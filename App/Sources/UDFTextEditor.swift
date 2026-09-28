import SignCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Holds the editor's text view and applies formatting to the selection.
@MainActor
final class UDFEditorController: ObservableObject {
    #if canImport(AppKit)
    weak var textView: NSTextView?
    #elseif canImport(UIKit)
    weak var textView: UITextView?
    #endif

    /// The current document text and styling as an attributed string.
    func attributedString() -> NSAttributedString {
        guard let textView, let storage = textStorage(textView) else { return NSAttributedString() }
        return storage.copy() as? NSAttributedString ?? NSAttributedString()
    }

    func setAttributedString(_ value: NSAttributedString) {
        #if canImport(AppKit)
        textView?.textStorage?.setAttributedString(value)
        #elseif canImport(UIKit)
        textView?.textStorage.setAttributedString(value)
        #endif
    }

    func toggleBold() { applyTrait(bold: true) }
    func toggleItalic() { applyTrait(italic: true) }

    func setSize(_ size: CGFloat) {
        modifyFonts { font in
            UDFFont(descriptor: font.fontDescriptor, size: size) ?? font
        }
    }

    private func applyTrait(bold: Bool = false, italic: Bool = false) {
        modifyFonts { font in
            let traits = fontTraits(font)
            let newBold = bold ? !traits.bold : traits.bold
            let newItalic = italic ? !traits.italic : traits.italic
            return makeFont(
                family: font.familyName ?? "Helvetica",
                size: font.pointSize,
                bold: newBold,
                italic: newItalic
            )
        }
    }

    func setFontFamily(_ family: String) {
        modifyFonts { font in
            let traits = fontTraits(font)
            return makeFont(family: family, size: font.pointSize, bold: traits.bold, italic: traits.italic)
        }
    }

    func toggleUnderline() {
        guard let textView, let storage = textStorage(textView) else { return }
        let range = selectedRange(textView)
        guard range.length > 0 else { return }
        let current = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        let value = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage.addAttribute(.underlineStyle, value: value, range: range)
    }

    func setForegroundColor(_ color: UDFColor) {
        applyToSelection(.foregroundColor, color)
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        applyParagraphStyle { $0.alignment = alignment }
    }

    func toggleUnderlineStrikethrough(strikethrough: Bool) {
        let key: NSAttributedString.Key = strikethrough ? .strikethroughStyle : .underlineStyle
        guard let textView, let storage = textStorage(textView) else { return }
        let range = selectedRange(textView)
        guard range.length > 0 else { return }
        let current = storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0
        storage.addAttribute(key, value: current == 0 ? NSUnderlineStyle.single.rawValue : 0, range: range)
    }

    func setHighlightColor(_ color: UDFColor) {
        applyToSelection(.backgroundColor, color)
    }

    func makeList(numbered: Bool) {
        let format: NSTextList.MarkerFormat = numbered ? .decimal : .disc
        applyParagraphStyle { style in
            style.textLists = [NSTextList(markerFormat: format, options: 0)]
            style.firstLineHeadIndent = 12
            style.headIndent = 24
        }
    }

    func indent(by delta: CGFloat) {
        applyParagraphStyle { style in
            style.firstLineHeadIndent = max(0, style.firstLineHeadIndent + delta)
            style.headIndent = max(0, style.headIndent + delta)
        }
    }

    func setLineSpacing(_ spacing: CGFloat) {
        applyParagraphStyle { $0.lineSpacing = spacing }
    }

    func toggleBaseline(superscript: Bool) {
        guard let textView, let storage = textStorage(textView) else { return }
        let range = selectedRange(textView)
        guard range.length > 0 else { return }
        let current = storage.attribute(.baselineOffset, at: range.location, effectiveRange: nil) as? CGFloat ?? 0
        let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? UDFFont
        let magnitude = (font?.pointSize ?? 12) * 0.35
        let target = superscript ? magnitude : -magnitude
        storage.addAttribute(.baselineOffset, value: current == 0 ? target : 0, range: range)
    }

    func insertImage(data: Data) {
        guard let textView, let storage = textStorage(textView), let image = platformImage(data) else { return }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = fittedBounds(imageSize(image))
        storage.insert(NSAttributedString(attachment: attachment), at: selectedRange(textView).location)
    }

    /// Scales every image in the selection by the given factor, keeping tables
    /// and other block attachments (which carry no image) untouched.
    func resizeSelectedImage(scale: CGFloat) {
        guard let textView, let storage = textStorage(textView) else { return }
        let range = selectedRange(textView)
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.attachment, in: range) { value, subRange, _ in
            guard let attachment = value as? NSTextAttachment, attachment.image != nil else { return }
            let bounds = attachment.bounds
            attachment.bounds = CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale)
            storage.edited(.editedAttributes, range: subRange, changeInLength: 0)
        }
        storage.endEditing()
    }

    private func fittedBounds(_ size: CGSize) -> CGRect {
        let maxWidth: CGFloat = 320
        guard size.width > maxWidth, size.width > 0 else {
            return CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let scale = maxWidth / size.width
        return CGRect(x: 0, y: 0, width: maxWidth, height: size.height * scale)
    }

    func insertTable(_ table: UDFTable) {
        guard let textView, let storage = textStorage(textView) else { return }
        storage.insert(UDFAttributedText.tableString(table), at: selectedRange(textView).location)
    }

    func selectedTable() -> UDFTable? { tableHit()?.table }

    func replaceSelectedTable(with table: UDFTable) {
        guard let textView, let storage = textStorage(textView), let range = tableHit()?.range else { return }
        storage.replaceCharacters(in: range, with: UDFAttributedText.tableString(table))
    }

    private func tableHit() -> (table: UDFTable, range: NSRange)? {
        guard let textView, let storage = textStorage(textView), storage.length > 0 else { return nil }
        let selected = selectedRange(textView)
        let scan = scanRange(selected, length: storage.length)
        var hit: (UDFTable, NSRange)?
        storage.enumerateAttribute(.attachment, in: scan) { value, subRange, stop in
            if let attachment = value as? NSTextAttachment, let table = UDFAttributedText.table(in: attachment) {
                hit = (table, subRange)
                stop.pointee = true
            }
        }
        return hit
    }

    private func scanRange(_ selected: NSRange, length: Int) -> NSRange {
        if selected.length > 0 { return selected }
        if selected.location < length { return NSRange(location: selected.location, length: 1) }
        return NSRange(location: selected.location - 1, length: 1)
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    private func applyToSelection(_ key: NSAttributedString.Key, _ value: Any) {
        guard let textView, let storage = textStorage(textView) else { return }
        let range = selectedRange(textView)
        guard range.length > 0 else { return }
        storage.addAttribute(key, value: value, range: range)
    }

    private func applyParagraphStyle(_ transform: (NSMutableParagraphStyle) -> Void) {
        guard let textView, let storage = textStorage(textView), storage.length > 0 else { return }
        let selected = selectedRange(textView)
        let base = selected.length > 0 ? selected : NSRange(location: 0, length: storage.length)
        let target = (storage.string as NSString).paragraphRange(for: base)
        storage.enumerateAttribute(.paragraphStyle, in: target) { value, subRange, _ in
            let style =
                (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            transform(style)
            storage.addAttribute(.paragraphStyle, value: style, range: subRange)
        }
    }

    private func modifyFonts(_ transform: (UDFFont) -> UDFFont) {
        guard let textView, let storage = textStorage(textView) else { return }
        let range = selectedRange(textView)
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let font = (value as? UDFFont) ?? makeFont(family: "Helvetica", size: 12, bold: false, italic: false)
            storage.addAttribute(.font, value: transform(font), range: subRange)
        }
        storage.endEditing()
    }

    #if canImport(AppKit)
    private func textStorage(_ view: NSTextView) -> NSTextStorage? { view.textStorage }
    private func selectedRange(_ view: NSTextView) -> NSRange { view.selectedRange() }
    private func platformImage(_ data: Data) -> NSImage? { NSImage(data: data) }
    private func imageSize(_ image: NSImage) -> CGSize { image.size }
    #elseif canImport(UIKit)
    private func textStorage(_ view: UITextView) -> NSTextStorage? { view.textStorage }
    private func selectedRange(_ view: UITextView) -> NSRange { view.selectedRange }
    private func platformImage(_ data: Data) -> UIImage? { UIImage(data: data) }
    private func imageSize(_ image: UIImage) -> CGSize { image.size }
    #endif
}

/// A rich-text editor backed by TextKit, shared across macOS and iOS.
struct UDFTextEditor: PlatformViewRepresentable {
    @ObservedObject var controller: UDFEditorController
    let initial: NSAttributedString

    #if canImport(AppKit)
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = true
        textView.allowsUndo = true
        textView.textStorage?.setAttributedString(initial)
        textView.font = NSFont.systemFont(ofSize: 13)
        controller.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
    #elseif canImport(UIKit)
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.textStorage.setAttributedString(initial)
        controller.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}
    #endif
}
