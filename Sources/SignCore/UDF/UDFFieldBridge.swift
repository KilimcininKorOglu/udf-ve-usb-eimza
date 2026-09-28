import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Dynamic-field helpers. A field is a placeholder such as the court's name or
/// the current date that the reader fills automatically; the editor inserts it
/// as marked text so it round-trips back to a `<field>` element carrying its
/// `fieldName`.
extension UDFAttributedText {
    public static func fieldString(name: String, placeholder: String) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: makeFont(family: "Helvetica", size: 12, bold: false, italic: false),
            .foregroundColor: UDFColor.systemBlue,
            .udfField: [UDFAttribute("fieldName", name)],
        ]
        return NSAttributedString(string: placeholder, attributes: attributes)
    }
}
