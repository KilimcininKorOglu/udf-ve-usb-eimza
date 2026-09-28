import Foundation

/// Page-furniture helpers: read and build the text of a header or footer
/// section. A section holds paragraphs like a table cell, so its text is
/// resolved and carried the same way.
extension UDFAttributedText {
    public static func sectionText(_ section: UDFSection, source: String) -> String {
        let text = source as NSString
        var parts: [String] = []
        for element in section.elements {
            guard case .paragraph(let paragraph) = element else { continue }
            parts.append(paragraph.textRuns.map { UDFTextReflow.text(of: $0, source: text) }.joined())
        }
        return parts.joined(separator: "\n")
    }

    /// Builds a section with a single paragraph holding the given text, keeping
    /// the section's own attributes (for example `startPage`).
    public static func makeSection(text: String, keeping attributes: [UDFAttribute]) -> UDFSection {
        guard !text.isEmpty else { return UDFSection(attributes: attributes, elements: []) }
        let run = UDFContentRun(startOffset: 0, length: 0, attributes: [UDFAttribute(UDFTextReflow.textKey, text)])
        return UDFSection(attributes: attributes, elements: [.paragraph(UDFParagraph(inlines: [.content(run)]))])
    }
}
