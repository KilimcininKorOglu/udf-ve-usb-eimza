import SignCore
import SwiftUI

/// A sheet that builds or edits a table as a grid of plain-text cells. Rows and
/// columns can be added or removed, and each cell is edited in place.
struct TableEditorSheet: View {
    @State private var grid: [[String]]
    let title: String
    let onDone: (UDFTable) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initial: [[String]]?, title: String, onDone: @escaping (UDFTable) -> Void) {
        _grid = State(initialValue: TableEditorSheet.normalized(initial))
        self.title = title
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            ScrollView([.horizontal, .vertical]) { gridView }
            Divider()
            controls
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 320)
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("Vazgeç") { dismiss() }
            Button("Uygula") {
                onDone(UDFAttributedText.makeTable(rows: grid))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var gridView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(grid.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(grid[row].indices, id: \.self) { column in
                        TextField("Hücre", text: $grid[row][column])
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Satır ekle") { addRow() }
            Button("Satır sil") { removeRow() }
            Button("Sütun ekle") { addColumn() }
            Button("Sütun sil") { removeColumn() }
        }
        .buttonStyle(.bordered)
    }

    private func addRow() { grid.append(Array(repeating: "", count: columnCount)) }

    private func removeRow() { if grid.count > 1 { grid.removeLast() } }

    private func addColumn() {
        for index in grid.indices { grid[index].append("") }
    }

    private func removeColumn() {
        guard columnCount > 1 else { return }
        for index in grid.indices where !grid[index].isEmpty { grid[index].removeLast() }
    }

    private var columnCount: Int { grid.first?.count ?? 1 }

    private static func normalized(_ initial: [[String]]?) -> [[String]] {
        guard let initial, !initial.isEmpty, !initial[0].isEmpty else {
            return [["", ""], ["", ""]]
        }
        return initial
    }
}
