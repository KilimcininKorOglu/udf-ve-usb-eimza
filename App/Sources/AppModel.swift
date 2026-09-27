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
}

/// The government sites the app can open.
struct SignSite: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
}

enum SignSites {
    static let all: [SignSite] = [
        SignSite(name: "e-Devlet", url: URL(string: "https://www.turkiye.gov.tr")!),
        SignSite(name: "UYAP Avukat", url: URL(string: "https://avukat.uyap.gov.tr")!),
        SignSite(name: "e-Tebligat", url: URL(string: "https://ptt.etebligat.gov.tr")!),
    ]
}
