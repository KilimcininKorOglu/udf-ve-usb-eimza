import SignCore
import SwiftUI
import UniformTypeIdentifiers

/// A full UDF editor: opens a `.udf` document into a TextKit view, edits its
/// rich text with a formatting toolbar, and writes it back to a `.udf` archive.
struct UDFEditorView: View {
    @StateObject private var controller = UDFEditorController()

    @State private var initial = NSAttributedString(string: "")
    @State private var documentID = UUID()
    @State private var pageFormat: [UDFAttribute] = []
    @State private var fileName = "belge.udf"
    @State private var fontSize: CGFloat = 13
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: UDFFileDocument?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            UDFTextEditor(controller: controller, initial: initial)
                .id(documentID)
        }
        .navigationTitle("UDF Editör")
        .fileImporter(isPresented: $importing, allowedContentTypes: udfTypes) { handleOpen($0) }
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
        HStack(spacing: 12) {
            Button {
                newDocument()
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("Yeni belge")
            Button {
                importing = true
            } label: {
                Image(systemName: "folder")
            }
            .help("Belge aç")
            Button {
                save()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Kaydet")

            Divider().frame(height: 18)

            Button {
                controller.toggleBold()
            } label: {
                Image(systemName: "bold")
            }
            .help("Kalın")
            Button {
                controller.toggleItalic()
            } label: {
                Image(systemName: "italic")
            }
            .help("İtalik")

            Picker("Boyut", selection: $fontSize) {
                ForEach([9, 10, 11, 12, 13, 14, 16, 18, 24, 36] as [CGFloat], id: \.self) { size in
                    Text("\(Int(size))").tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 70)
            .onChange(of: fontSize) { newValue in controller.setSize(newValue) }

            Spacer()
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
    }

    private func newDocument() {
        initial = NSAttributedString(string: "", attributes: [.font: defaultFont])
        pageFormat = []
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
            pageFormat = document.pageFormat
            fileName = url.lastPathComponent
            message = nil
            documentID = UUID()
        } catch {
            message = "Belge açılamadı"
        }
    }

    private func save() {
        let attributed = controller.attributedString()
        let document = UDFAttributedText.document(from: attributed, pageFormat: pageFormat)
        do {
            let data = try UDFWriter.write(document)
            exportDocument = UDFFileDocument(data: data)
            exporting = true
            message = "Kaydedilmeye hazır"
        } catch {
            message = "Belge yazılamadı"
        }
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
