import SignCore
import SwiftUI
import UniformTypeIdentifiers

/// Signs a local document with a card certificate.
struct DocumentSignView: View {
    @EnvironmentObject private var model: AppModel

    @State private var fileURL: URL?
    @State private var fileData: Data?
    @State private var certificates: [CertificateEntry] = []
    @State private var selectedCertID: String = ""
    @State private var pin: String = ""
    @State private var format: SignatureType = .cades
    @State private var importing = false
    @State private var exporting = false
    @State private var working = false
    @State private var message: String?
    @State private var signed: SignedDocument?

    var body: some View {
        Form {
            documentSection
            certificateSection
            formatSection
            actionSection
            if let message {
                Section { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Belge İmzala")
        .task { await loadCertificates() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { handleImport($0) }
        .fileExporter(
            isPresented: $exporting,
            document: signed,
            contentType: .data,
            defaultFilename: exportName
        ) { _ in }
    }

    private var documentSection: some View {
        Section("Belge") {
            Button {
                importing = true
            } label: {
                Label(fileURL?.lastPathComponent ?? "Bir belge seçin", systemImage: "doc.badge.plus")
            }
        }
    }

    private var certificateSection: some View {
        Section("Sertifika") {
            if certificates.isEmpty {
                Text("Kart bekleniyor").foregroundStyle(.secondary)
            } else {
                Picker("Sertifika", selection: $selectedCertID) {
                    ForEach(certificates, id: \.certificateId) { cert in
                        Text(certLabel(cert)).tag(cert.certificateId)
                    }
                }
            }
            SecureField("PIN", text: $pin)
        }
    }

    private var formatSection: some View {
        Section("Biçim") {
            Picker("Biçim", selection: $format) {
                Text("CAdES").tag(SignatureType.cades)
                Text("XAdES").tag(SignatureType.xades)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var actionSection: some View {
        Section {
            Button(action: sign) {
                HStack {
                    Text("İmzala")
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                }
            }
            .disabled(!canSign)
        }
    }

    private var canSign: Bool {
        fileData != nil && !selectedCertID.isEmpty && !pin.isEmpty && !working
    }

    private var exportName: String {
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "imza"
        return format == .cades ? "\(base).p7s" : "\(base).xml"
    }

    private func certLabel(_ cert: CertificateEntry) -> String {
        let tckn = cert.tckn.map { " · \($0)" } ?? ""
        return cert.subject + tckn
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        fileURL = url
        fileData = try? Data(contentsOf: url)
        message = fileData == nil ? "Belge okunamadı" : nil
    }

    private func loadCertificates() async {
        let list = await model.certificates()
        await MainActor.run {
            certificates = list
            if let first = list.first { selectedCertID = first.certificateId }
        }
    }

    private func sign() {
        guard let data = fileData else { return }
        working = true
        message = nil
        Task {
            let result = await model.sign(content: data, certificateId: selectedCertID, pin: pin, type: format)
            await MainActor.run {
                working = false
                switch result {
                case .success(let output):
                    signed = SignedDocument(data: output)
                    exporting = true
                    message = "İmza oluşturuldu"
                case .failure(let reason):
                    message = reason
                }
            }
        }
    }
}

/// A signed document for the file exporter.
struct SignedDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
