import SwiftUI
import SignCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSite = SignSites.all[0]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            WebContainer(url: selectedSite.url, router: model.router)
                .id(selectedSite.id)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Site", selection: $selectedSite) {
                ForEach(SignSites.all) { site in
                    Text(site.name).tag(site)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            Spacer()
            statusBadge
        }
        .padding(10)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: model.cardStatus))
                .frame(width: 10, height: 10)
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for status: CardStatus) -> Color {
        switch status {
        case .present: return .green
        case .reading: return .yellow
        case .absent: return .gray
        case .error: return .red
        }
    }
}
