import Foundation

/// Rebuilds the single flat document text and re-assigns every run's offset.
///
/// UDF keeps one flat text and every run (in a body paragraph, a table cell or a
/// header/footer) points at a range of it. After an edit the body text is fresh
/// while a carried element (a table) still points at the original text, so a
/// single pass walks the whole element tree in document order, resolves each
/// run's characters, appends them to the new text and stores the new offset.
enum UDFTextReflow {
    /// Attribute name that carries a freshly edited run's literal text until the
    /// flatten pass consumes it. A run without it is resolved from `source`.
    static let textKey = "_text"

    static func flatten(_ elements: [UDFElement], source: NSString, into text: inout String) -> [UDFElement] {
        elements.map { element(from: $0, source: source, into: &text) }
    }

    private static func element(from element: UDFElement, source: NSString, into text: inout String) -> UDFElement {
        switch element {
        case .paragraph(let paragraph):
            return .paragraph(
                UDFParagraph(attributes: paragraph.attributes, inlines: inlines(paragraph.inlines, source, &text)))
        case .table(let table):
            return .table(self.table(table, source, &text))
        case .field(let field):
            return .field(UDFField(attributes: field.attributes, runs: runs(field.runs, source, &text)))
        case .space(let value):
            return .space(run(value, source, &text))
        case .header(let section):
            return .header(self.section(section, source, &text))
        case .footer(let section):
            return .footer(self.section(section, source, &text))
        case .image, .raw:
            return element
        }
    }

    private static func inlines(_ inlines: [UDFInline], _ source: NSString, _ text: inout String) -> [UDFInline] {
        inlines.map { inline in
            switch inline {
            case .content(let value): return .content(run(value, source, &text))
            case .field(let value): return .field(run(value, source, &text))
            case .space(let value): return .space(run(value, source, &text))
            case .image, .raw: return inline
            }
        }
    }

    private static func table(_ table: UDFTable, _ source: NSString, _ text: inout String) -> UDFTable {
        let rows = table.rows.map { row -> UDFRow in
            let cells = row.cells.map { cell in
                UDFCell(attributes: cell.attributes, elements: flatten(cell.elements, source: source, into: &text))
            }
            return UDFRow(attributes: row.attributes, cells: cells)
        }
        return UDFTable(attributes: table.attributes, rows: rows)
    }

    private static func section(_ section: UDFSection, _ source: NSString, _ text: inout String) -> UDFSection {
        UDFSection(attributes: section.attributes, elements: flatten(section.elements, source: source, into: &text))
    }

    private static func runs(_ runs: [UDFContentRun], _ source: NSString, _ text: inout String) -> [UDFContentRun] {
        runs.map { run($0, source, &text) }
    }

    private static func run(_ run: UDFContentRun, _ source: NSString, _ text: inout String) -> UDFContentRun {
        let characters = self.text(of: run, source: source)
        let start = (text as NSString).length
        text += characters
        let length = (characters as NSString).length
        let attributes = run.attributes.filter { $0.name != textKey }
        return UDFContentRun(startOffset: start, length: length, attributes: attributes)
    }

    /// The literal characters of a run: the freshly edited text if present,
    /// otherwise the slice of the original document text at the run's range.
    static func text(of run: UDFContentRun, source: NSString) -> String {
        run.attributes.value(textKey)
            ?? safeSubstring(source, offset: run.startOffset, length: run.length)
            ?? ""
    }
}
