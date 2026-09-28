import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension NSAttributedString.Key {
    /// UDF `<field>` run attributes (for example `fieldName`) carried on the
    /// rendered field text so a field round-trips back to a `<field>` inline.
    static let udfField = NSAttributedString.Key("udfField")
    /// Paragraph-level UDF attributes that are not mapped onto `NSParagraphStyle`
    /// (the `resolver` style name and any others), carried across the paragraph
    /// range so they survive an edit.
    static let udfParagraphMeta = NSAttributedString.Key("udfParagraphMeta")
}

/// A text attachment that carries a structural UDF element (a table, or any
/// element outside the flowing-text set) through the editable text, so it keeps
/// its position in document order and round-trips without loss.
final class UDFElementAttachment: NSTextAttachment {
    let element: UDFElement

    init(element: UDFElement) {
        self.element = element
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// The 0-255 colour channels of a `UDFColor`.
private struct ColorChannels {
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Int
}

/// Serialises a colour as a signed 32-bit ARGB integer string, the UDF form
/// produced by a Color-to-int conversion (for example black is "-16777216").
func udfColorString(_ color: UDFColor) -> String {
    let channels = rgbaChannels(color)
    let alpha = UInt32(channels.alpha) << 24
    let red = UInt32(channels.red) << 16
    let green = UInt32(channels.green) << 8
    let blue = UInt32(channels.blue)
    let argb: UInt32 = alpha | red | green | blue
    return String(Int32(bitPattern: argb))
}

private func rgbaChannels(_ color: UDFColor) -> ColorChannels {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    #if canImport(AppKit)
    let source = color.usingColorSpace(.sRGB) ?? color
    source.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    #elseif canImport(UIKit)
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    #endif
    return ColorChannels(red: channel(red), green: channel(green), blue: channel(blue), alpha: channel(alpha))
}

private func channel(_ value: CGFloat) -> Int {
    Int((max(0, min(1, value)) * 255).rounded())
}

// MARK: Platform image helpers

#if canImport(AppKit)
func platformImage(from data: Data) -> NSImage? { NSImage(data: data) }

func setAttachmentImage(_ attachment: NSTextAttachment, _ image: NSImage) { attachment.image = image }

func attachmentPNGData(_ attachment: NSTextAttachment) -> Data? {
    guard let image = attachment.image, let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
}
#elseif canImport(UIKit)
func platformImage(from data: Data) -> UIImage? { UIImage(data: data) }

func setAttachmentImage(_ attachment: NSTextAttachment, _ image: UIImage) { attachment.image = image }

func attachmentPNGData(_ attachment: NSTextAttachment) -> Data? {
    attachment.image?.pngData()
}
#endif
