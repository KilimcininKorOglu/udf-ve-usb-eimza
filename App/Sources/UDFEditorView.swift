import SignCore
import SwiftUI
import UniformTypeIdentifiers

/// A full UDF editor: opens a `.udf` document into a TextKit view, edits its
/// rich text with a formatting toolbar, and writes it back to a `.udf` archive.
struct UDFEditorView: View {
    @StateObject private var controller = UDFEditorController()

    @State private var initial = NSAttributedString(string: "")
    @State private var documentID = UUID()
    @State private var template = UDFDocument()
    @State private var fileName = "belge.udf"
    @State private var fontFamily = "Helvetica"
    @State private var fontSize: CGFloat = 13
    @State private var textColor = Color.primary
    @State private var highlightColor = Color.yellow
    @State private var importing = false
    @State private var importingImage = false
    @State private var exporting = false
    @State private var exportDocument: UDFFileDocument?
    @State private var message: String?

    private let families = [
        "Helvetica", "Arial", "Times New Roman", "Georgia", "Courier New", "Verdana",
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            UDFTextEditor(controller: controller, initial: initial)
                .id(documentID)
        }
        .navigationTitle("UDF Editör")
        .fileImporter(isPresented: $importing, allowedContentTypes: udfTypes) { handleOpen($0) }
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image]) { handleImage($0) }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: udfTypes.first ?? .data,
            defaultFilename: fileName
        ) { _ in }
    }

    private var udfTypes: [UTType] {
        [UTType(filenameExtension: "udf") ?? .data]
    }

    private var toolbar: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    fileGroup
                    bar
                    historyGroup
                    bar
                    fontGroup
                    bar
                    styleGroup
                    bar
                    colorGroup
                    bar
                    alignGroup
                    bar
                    listGroup
                    bar
                    spacingGroup
                    bar
                    insertGroup
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .buttonStyle(.borderless)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var bar: some View { Divider().frame(height: 20) }

    private func toolButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22) }.help(help)
    }

    private var fileGroup: some View {
        HStack(spacing: 8) {
            toolButton("doc.badge.plus", "Yeni belge") { newDocument() }
            toolButton("folder", "Belge aç") { importing = true }
            toolButton("square.and.arrow.down", "Kaydet") { save() }
        }
    }

    private var historyGroup: some View {
        HStack(spacing: 8) {
            toolButton("arrow.uturn.backward", "Geri al") { controller.undo() }
            toolButton("arrow.uturn.forward", "İleri al") { controller.redo() }
        }
    }

    private var fontGroup: some View {
        HStack(spacing: 8) {
            Picker("Yazı tipi", selection: $fontFamily) {
                ForEach(families, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 140)
            .onChange(of: fontFamily) { controller.setFontFamily($0) }

            Picker("Boyut", selection: $fontSize) {
                ForEach([8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 36, 48] as [CGFloat], id: \.self) {
                    Text("\(Int($0))").tag($0)
                }
            }
            .labelsHidden().frame(width: 64)
            .onChange(of: fontSize) { controller.setSize($0) }
        }
    }

    private var styleGroup: some View {
        HStack(spacing: 8) {
            toolButton("bold", "Kalın") { controller.toggleBold() }
            toolButton("italic", "İtalik") { controller.toggleItalic() }
            toolButton("underline", "Altı çizili") { controller.toggleUnderlineStrikethrough(strikethrough: false) }
            toolButton("strikethrough", "Üstü çizili") { controller.toggleUnderlineStrikethrough(strikethrough: true) }
            toolButton("textformat.superscript", "Üst simge") { controller.toggleBaseline(superscript: true) }
            toolButton("textformat.subscript", "Alt simge") { controller.toggleBaseline(superscript: false) }
        }
    }

    private var spacingGroup: some View {
        Menu {
            Button("Tek") { controller.setLineSpacing(0) }
            Button("1,5 satır") { controller.setLineSpacing(6) }
            Button("Çift") { controller.setLineSpacing(12) }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal").frame(width: 22)
        }
        .menuIndicator(.hidden)
        .help("Satır aralığı")
    }

    private var colorGroup: some View {
        HStack(spacing: 8) {
            ColorPicker("Metin rengi", selection: $textColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: textColor) { controller.setForegroundColor(platformColor($0)) }
            ColorPicker("Vurgu", selection: $highlightColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: highlightColor) { controller.setHighlightColor(platformColor($0)) }
        }
    }

    private var alignGroup: some View {
        HStack(spacing: 8) {
            toolButton("text.alignleft", "Sola") { controller.setAlignment(.left) }
            toolButton("text.aligncenter", "Ortala") { controller.setAlignment(.center) }
            toolButton("text.alignright", "Sağa") { controller.setAlignment(.right) }
            toolButton("text.justify", "İki yana") { controller.setAlignment(.justified) }
        }
    }

    private var listGroup: some View {
        HStack(spacing: 8) {
            toolButton("list.bullet", "Madde listesi") { controller.makeList(numbered: false) }
            toolButton("list.number", "Numaralı liste") { controller.makeList(numbered: true) }
            toolButton("decrease.indent", "Girintiyi azalt") { controller.indent(by: -24) }
            toolButton("increase.indent", "Girinti ekle") { controller.indent(by: 24) }
        }
    }

    private var insertGroup: some View {
        HStack(spacing: 8) {
            toolButton("photo", "Resim ekle") { importingImage = true }
            toolButton("plus.magnifyingglass", "Resmi büyüt") { controller.resizeSelectedImage(scale: 1.25) }
            toolButton("minus.magnifyingglass", "Resmi küçült") { controller.resizeSelectedImage(scale: 0.8) }
        }
    }

    private func newDocument() {
        initial = NSAttributedString(string: "", attributes: [.font: defaultFont])
        template = UDFDocument(styles: [UDFStyle(name: "default", attributes: [])])
        fileName = "belge.udf"
        message = nil
        documentID = UUID()
    }

    private func handleOpen(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let document = try UDFReader.read(udf: data)
            initial = UDFAttributedText.attributedString(from: document)
            template = document
            fileName = url.lastPathComponent
            message = nil
            documentID = UUID()
        } catch {
            message = "Belge açılamadı"
        }
    }

    private func save() {
        let attributed = controller.attributedString()
        let document = UDFAttributedText.document(from: attributed, template: template)
        do {
            let data = try UDFWriter.write(document)
            exportDocument = UDFFileDocument(data: data)
            exporting = true
            message = "Kaydedilmeye hazır"
        } catch {
            message = "Belge yazılamadı"
        }
    }

    private func handleImage(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            message = "Resim okunamadı"
            return
        }
        controller.insertImage(data: data)
    }

    private var defaultFont: UDFFont {
        makeFont(family: "Helvetica", size: fontSize, bold: false, italic: false)
    }
}

/// A `.udf` archive wrapper for the file exporter.
struct UDFFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [UTType(filenameExtension: "udf") ?? .data]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if canImport(AppKit)
import AppKit
private func platformColor(_ color: Color) -> UDFColor { NSColor(color) }
#elseif canImport(UIKit)
import UIKit
private func platformColor(_ color: Color) -> UDFColor { UIColor(color) }
#endif
