import SignCore
import SwiftUI

/// A sheet that edits the page format (paper size, margins, orientation and the
/// header/footer offsets) and the header and footer text. It returns an updated
/// template that the editor uses on the next save.
struct PageSetupView: View {
    let template: UDFDocument
    let onApply: (UDFDocument) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mediaSize: String
    @State private var leftMargin: String
    @State private var rightMargin: String
    @State private var topMargin: String
    @State private var bottomMargin: String
    @State private var orientation: String
    @State private var headerText: String
    @State private var footerText: String

    init(template: UDFDocument, onApply: @escaping (UDFDocument) -> Void) {
        self.template = template
        self.onApply = onApply
        let format = template.pageFormat
        _mediaSize = State(initialValue: format.value("mediaSizeName") ?? "A4")
        _leftMargin = State(initialValue: format.value("leftMargin") ?? "")
        _rightMargin = State(initialValue: format.value("rightMargin") ?? "")
        _topMargin = State(initialValue: format.value("topMargin") ?? "")
        _bottomMargin = State(initialValue: format.value("bottomMargin") ?? "")
        _orientation = State(initialValue: format.value("orientation") ?? "portrait")
        _headerText = State(initialValue: PageSetupView.text(of: .header, in: template))
        _footerText = State(initialValue: PageSetupView.text(of: .footer, in: template))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sayfa düzeni").font(.headline)
                Spacer()
                Button("Vazgeç") { dismiss() }
                Button("Uygula") { apply() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            form
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private var form: some View {
        Form {
            Section("Sayfa") {
                TextField("Kağıt boyutu", text: $mediaSize)
                Picker("Yönelim", selection: $orientation) {
                    Text("Dikey").tag("portrait")
                    Text("Yatay").tag("landscape")
                }
            }
            Section("Kenar boşlukları") {
                TextField("Sol", text: $leftMargin)
                TextField("Sağ", text: $rightMargin)
                TextField("Üst", text: $topMargin)
                TextField("Alt", text: $bottomMargin)
            }
            Section("Üstbilgi ve altbilgi") {
                TextField("Üstbilgi", text: $headerText)
                TextField("Altbilgi", text: $footerText)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apply

    private func apply() {
        var document = template
        document.pageFormat = updatedFormat()
        document.elements = updatedElements()
        onApply(document)
        dismiss()
    }

    private func updatedFormat() -> [UDFAttribute] {
        var format = template.pageFormat
        format = upsert(format, "mediaSizeName", mediaSize)
        format = upsert(format, "orientation", orientation)
        format = upsert(format, "leftMargin", leftMargin)
        format = upsert(format, "rightMargin", rightMargin)
        format = upsert(format, "topMargin", topMargin)
        format = upsert(format, "bottomMargin", bottomMargin)
        return format
    }

    private func upsert(_ attributes: [UDFAttribute], _ name: String, _ value: String) -> [UDFAttribute] {
        guard !value.isEmpty else { return attributes }
        var result = attributes.filter { $0.name != name }
        result.append(UDFAttribute(name, value))
        return result
    }

    private func updatedElements() -> [UDFElement] {
        var body = template.elements.filter { !isSection($0) }
        body.insert(.header(section(.header, text: headerText)), at: 0)
        body.append(.footer(section(.footer, text: footerText)))
        return body
    }

    private func section(_ kind: SectionKind, text: String) -> UDFSection {
        let attributes = PageSetupView.section(kind, in: template)?.attributes ?? [UDFAttribute("startPage", "1")]
        return UDFAttributedText.makeSection(text: text, keeping: attributes)
    }

    private func isSection(_ element: UDFElement) -> Bool {
        switch element {
        case .header, .footer: return true
        default: return false
        }
    }

    // MARK: Reading the template

    private enum SectionKind { case header, footer }

    private static func section(_ kind: SectionKind, in template: UDFDocument) -> UDFSection? {
        for element in template.elements {
            switch (kind, element) {
            case (.header, .header(let value)): return value
            case (.footer, .footer(let value)): return value
            default: continue
            }
        }
        return nil
    }

    private static func text(of kind: SectionKind, in template: UDFDocument) -> String {
        guard let section = section(kind, in: template) else { return "" }
        return UDFAttributedText.sectionText(section, source: template.text)
    }
}
