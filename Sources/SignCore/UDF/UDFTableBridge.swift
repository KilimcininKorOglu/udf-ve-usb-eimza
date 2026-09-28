import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Table creation, reading and editing helpers for the editor. A table travels
/// through the editable text as a rendered attachment; these functions build a
/// table from a plain-text grid, read one back as a grid, and pull a table out
/// of an attachment.
extension UDFAttributedText {
    /// A rendered attachment for a table, ready to insert into the editor.
    public static func tableString(_ table: UDFTable) -> NSAttributedString {
        NSAttributedString(attachment: UDFElementAttachment(element: .table(table), source: ""))
    }

    /// The table an attachment carries, if it is a table block.
    public static func table(in attachment: NSTextAttachment) -> UDFTable? {
        guard let block = attachment as? UDFElementAttachment, case .table(let table) = block.element else {
            return nil
        }
        return table
    }

    /// Builds a table from a grid of plain-text cells; each cell's text is
    /// carried on its run so it flows into the document text on save.
    public static func makeTable(rows: [[String]]) -> UDFTable {
        UDFTable(rows: rows.map { cells in UDFRow(cells: cells.map(cell(fromText:))) })
    }

    /// Reads a table's cell texts as a grid, resolving each cell against the
    /// given source (the document text a loaded table points into).
    public static func grid(of table: UDFTable, source: String) -> [[String]] {
        let text = source as NSString
        return table.rows.map { row in row.cells.map { cellText($0, source: text) } }
    }

    private static func cell(fromText text: String) -> UDFCell {
        guard !text.isEmpty else { return UDFCell(elements: [.paragraph(UDFParagraph(runs: []))]) }
        let run = UDFContentRun(startOffset: 0, length: 0, attributes: [UDFAttribute(UDFTextReflow.textKey, text)])
        return UDFCell(elements: [.paragraph(UDFParagraph(inlines: [.content(run)]))])
    }

    private static func cellText(_ cell: UDFCell, source: NSString) -> String {
        var parts: [String] = []
        for element in cell.elements {
            guard case .paragraph(let paragraph) = element else { continue }
            parts.append(paragraph.textRuns.map { UDFTextReflow.text(of: $0, source: source) }.joined())
        }
        return parts.joined(separator: "\n")
    }
}
