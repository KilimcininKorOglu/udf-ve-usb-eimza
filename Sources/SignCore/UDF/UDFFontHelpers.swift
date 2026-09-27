import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Returns the substring for a UTF-16 range, or nil when out of bounds.
func safeSubstring(_ source: NSString, offset: Int, length: Int) -> String? {
    guard offset >= 0, length >= 0, offset + length <= source.length else { return nil }
    return source.substring(with: NSRange(location: offset, length: length))
}

/// Parses a UDF foreground colour, either "#RRGGBB" or an ARGB integer.
func color(fromHex value: String) -> UDFColor? {
    if value.hasPrefix("#") {
        let hex = String(value.dropFirst())
        guard let rgb = Int(hex, radix: 16) else { return nil }
        return rgbColor(red: (rgb >> 16) & 0xFF, green: (rgb >> 8) & 0xFF, blue: rgb & 0xFF)
    }
    guard let argb = Int(value) else { return nil }
    return rgbColor(red: (argb >> 16) & 0xFF, green: (argb >> 8) & 0xFF, blue: argb & 0xFF)
}

private func rgbColor(red: Int, green: Int, blue: Int) -> UDFColor {
    UDFColor(
        red: CGFloat(red) / 255.0,
        green: CGFloat(green) / 255.0,
        blue: CGFloat(blue) / 255.0,
        alpha: 1.0
    )
}

#if canImport(AppKit)
func makeFont(family: String, size: CGFloat, bold: Bool, italic: Bool) -> UDFFont {
    var traits: NSFontDescriptor.SymbolicTraits = []
    if bold { traits.insert(.bold) }
    if italic { traits.insert(.italic) }
    let descriptor = NSFontDescriptor(fontAttributes: [.family: family]).withSymbolicTraits(traits)
    return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
}

func fontTraits(_ font: UDFFont) -> (bold: Bool, italic: Bool) {
    let traits = font.fontDescriptor.symbolicTraits
    return (traits.contains(.bold), traits.contains(.italic))
}
#elseif canImport(UIKit)
func makeFont(family: String, size: CGFloat, bold: Bool, italic: Bool) -> UDFFont {
    var traits: UIFontDescriptor.SymbolicTraits = []
    if bold { traits.insert(.traitBold) }
    if italic { traits.insert(.traitItalic) }
    var descriptor = UIFontDescriptor(fontAttributes: [.family: family])
    if let adjusted = descriptor.withSymbolicTraits(traits) { descriptor = adjusted }
    return UIFont(descriptor: descriptor, size: size)
}

func fontTraits(_ font: UDFFont) -> (bold: Bool, italic: Bool) {
    let traits = font.fontDescriptor.symbolicTraits
    return (traits.contains(.traitBold), traits.contains(.traitItalic))
}
#endif
