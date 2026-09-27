import Foundation
import SwiftUI
import SignCore

/// Owns the signing service, the loopback server and the live card status.
@MainActor
final class AppModel: ObservableObject {
    @Published var cardStatus: CardStatus = .absent
    @Published var statusMessage: String = "Kart bekleniyor"

    let router: Router
    private let service: CardSigningService
    private let server: LoopbackServer
    private var statusTask: Task<Void, Never>?

    init() {
        let service = CardSigningService(transport: TKSmartCardTransport())
        self.service = service
        self.router = Router(service: service)
        self.server = LoopbackServer(router: router)
    }

    func start() {
        try? server.start()
        statusTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.service.cardStatusStream() {
                await MainActor.run {
                    self.cardStatus = event.status
                    self.statusMessage = event.message ?? event.readerName ?? "Kart hazır"
                }
            }
        }
    }

    func stop() {
        statusTask?.cancel()
        server.stop()
    }

    /// One-shot reader probe for the diagnostics row.
    func probeReader() async -> String {
        let envelope = await service.listCertificates()
        switch envelope.metadata.status {
        case .ok:
            let count = envelope.data?.count ?? 0
            return "Okuyucu ve kart hazır. Sertifika: \(count)"
        default:
            return envelope.metadata.message ?? "Okuyucu bulunamadı"
        }
    }

    /// Certificates on the inserted card, empty when none are readable.
    func certificates() async -> [CertificateEntry] {
        (await service.listCertificates()).data ?? []
    }

    /// Signs content and returns the signed bytes or a message.
    func sign(content: Data, certificateId: String, pin: String, type: SignatureType) async -> SignOutcome {
        let request = SignRequest(
            certificateId: certificateId,
            password: pin,
            signatureType: type,
            contentBase64: content.base64EncodedString()
        )
        let envelope = await service.sign(request)
        guard envelope.metadata.status == .ok,
              let base64 = envelope.data?.signedDataBase64,
              let data = Data(base64Encoded: base64) else {
            return .failure(envelope.metadata.message ?? "İmza başarısız")
        }
        return .success(data)
    }
}

/// Result of a signing attempt for the UI.
enum SignOutcome {
    case success(Data)
    case failure(String)
}

/// A login portal reachable from the app.
struct Portal: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let url: URL
}

/// A hardware or setup requirement shown on the portals screen.
struct Requirement: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let text: String
}

enum PortalCatalog {
    static let portals: [Portal] = [
        Portal(name: "UYAP (Avukat Portal)", subtitle: nil,
               url: URL(string: "https://avukat.uyap.gov.tr")!),
        Portal(name: "e-Devlet", subtitle: nil,
               url: URL(string: "https://giris.turkiye.gov.tr")!),
        Portal(name: "UETS (e-Tebligat)", subtitle: nil,
               url: URL(string: "https://ptt.etebligat.gov.tr/login")!),
        Portal(name: "PTT KEP", subtitle: nil,
               url: URL(string: "https://ptt.hs01.kep.tr")!),
        Portal(name: "e-Devlet – kodu elle gir",
               subtitle: "Başka uygulamadaki girişin kodu (ör. Celse)",
               url: URL(string: "https://giris.turkiye.gov.tr")!),
    ]

    static let requirements: [Requirement] = [
        Requirement(symbol: "creditcard", text: "Nitelikli e-imza kartı ve PIN'i"),
        Requirement(symbol: "sdcard", text: "CCID uyumlu USB kart okuyucu (ör. ACR39U)"),
        Requirement(symbol: "cable.connector", text: "USB-C veya Lightning-USB adaptörü"),
    ]

    static let footer = """
    Giriş sayfasındaki işlem kodu okunur, imza kartla atılır ve sunucuya \
    gönderilir. Uygulama sayfaya müdahale etmez; girişi sayfa tamamlar. \
    PIN yalnız karta gider, kaydedilmez.
    """
}
