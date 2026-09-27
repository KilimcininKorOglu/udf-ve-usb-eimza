import SwiftUI
import SignCore

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
            return makeFont(family: font.familyName ?? "Helvetica", size: font.pointSize, bold: newBold, italic: newItalic)
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
    #elseif canImport(UIKit)
    private func textStorage(_ view: UITextView) -> NSTextStorage? { view.textStorage }
    private func selectedRange(_ view: UITextView) -> NSRange { view.selectedRange }
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
