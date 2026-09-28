import Foundation

#if canImport(AppKit)
import AppKit
private typealias RenderImage = NSImage
#elseif canImport(UIKit)
import UIKit
private typealias RenderImage = UIImage
#endif

/// Draws a `UDFTable` to a platform image for display inside the editor. The
/// grid honours `columnSpan` and `rowSpan`; cell text is resolved the same way
/// the reflow pass resolves it, so a newly created and a loaded table both draw.
enum UDFTableRenderer {
    static let columnWidth: CGFloat = 150
    static let rowHeight: CGFloat = 30

    private struct Placement {
        let cell: UDFCell
        let rect: CGRect
    }

    private struct TablePlan {
        let placements: [Placement]
        let columns: Int
        let rows: Int
    }

    static func size(of table: UDFTable) -> CGSize {
        planSize(layout(table))
    }

    static func image(of table: UDFTable, source: NSString) -> UDFTableImage? {
        let plan = layout(table)
        let size = planSize(plan)
        guard size.width > 0, size.height > 0 else { return nil }
        return makeImage(size: size) { draw(plan.placements, source: source, size: size) }
    }

    // MARK: Layout

    private static func planSize(_ plan: TablePlan) -> CGSize {
        CGSize(width: CGFloat(plan.columns) * columnWidth, height: CGFloat(plan.rows) * rowHeight)
    }

    private static func layout(_ table: UDFTable) -> TablePlan {
        var occupied: Set<Int> = []
        var placements: [Placement] = []
        var maxColumn = 0
        for (rowIndex, row) in table.rows.enumerated() {
            var column = 0
            for cell in row.cells {
                while occupied.contains(key(rowIndex, column)) { column += 1 }
                let columnSpan = span(cell, "columnSpan")
                let rowSpan = span(cell, "rowSpan")
                let box = rect(row: rowIndex, column: column, columnSpan: columnSpan, rowSpan: rowSpan)
                placements.append(Placement(cell: cell, rect: box))
                occupy(&occupied, row: rowIndex, column: column, columnSpan: columnSpan, rowSpan: rowSpan)
                maxColumn = max(maxColumn, column + columnSpan)
                column += columnSpan
            }
        }
        return TablePlan(placements: placements, columns: maxColumn, rows: table.rows.count)
    }

    private static func occupy(_ occupied: inout Set<Int>, row: Int, column: Int, columnSpan: Int, rowSpan: Int) {
        for deltaRow in 0..<rowSpan {
            for deltaColumn in 0..<columnSpan {
                occupied.insert(key(row + deltaRow, column + deltaColumn))
            }
        }
    }

    private static func rect(row: Int, column: Int, columnSpan: Int, rowSpan: Int) -> CGRect {
        CGRect(
            x: CGFloat(column) * columnWidth,
            y: CGFloat(row) * rowHeight,
            width: CGFloat(columnSpan) * columnWidth,
            height: CGFloat(rowSpan) * rowHeight
        )
    }

    private static func key(_ row: Int, _ column: Int) -> Int { row * 1000 + column }

    private static func span(_ cell: UDFCell, _ name: String) -> Int {
        max(1, Int(cell.attributes.value(name) ?? "1") ?? 1)
    }

    // MARK: Drawing

    private static func draw(_ placements: [Placement], source: NSString, size: CGSize) {
        fillBackground(size)
        for placement in placements {
            strokeBorder(placement.rect)
            drawText(cellText(placement.cell, source: source), in: placement.rect)
        }
    }

    private static func cellText(_ cell: UDFCell, source: NSString) -> String {
        var parts: [String] = []
        for element in cell.elements {
            guard case .paragraph(let paragraph) = element else { continue }
            parts.append(paragraph.textRuns.map { UDFTextReflow.text(of: $0, source: source) }.joined())
        }
        return parts.joined(separator: "\n")
    }

    private static func drawText(_ text: String, in rect: CGRect) {
        guard !text.isEmpty else { return }
        let inset = rect.insetBy(dx: 5, dy: 4)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: makeFont(family: "Helvetica", size: 12, bold: false, italic: false),
            .foregroundColor: UDFColor.black,
        ]
        (text as NSString).draw(in: inset, withAttributes: attributes)
    }
}

// MARK: Platform drawing

#if canImport(AppKit)
private func makeImage(size: CGSize, draw: () -> Void) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    draw()
    image.unlockFocus()
    return image
}

private func fillBackground(_ size: CGSize) {
    UDFColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
}

private func strokeBorder(_ rect: CGRect) {
    UDFColor.gray.setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = 1
    path.stroke()
}
#elseif canImport(UIKit)
private func makeImage(size: CGSize, draw: () -> Void) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in draw() }
}

private func fillBackground(_ size: CGSize) {
    UDFColor.white.setFill()
    UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
}

private func strokeBorder(_ rect: CGRect) {
    UDFColor.gray.setStroke()
    let path = UIBezierPath(rect: rect)
    path.lineWidth = 1
    path.stroke()
}
#endif

/// The platform image type the table renderer produces.
#if canImport(AppKit)
public typealias UDFTableImage = NSImage
#elseif canImport(UIKit)
public typealias UDFTableImage = UIImage
#endif
