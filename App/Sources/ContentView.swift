import SwiftUI
import SignCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: Tab = .portals

    enum Tab: Hashable { case portals, document }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Picker("", selection: $tab) {
                    Text("Portallar").tag(Tab.portals)
                    Text("Belge İmzala").tag(Tab.document)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                HStack {
                    Spacer()
                    StatusBadge()
                }
                .padding(.trailing, 12)
            }
            .padding(.vertical, 10)

            Divider()

            Group {
                switch tab {
                case .portals: PortalsView()
                case .document: DocumentSignView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, minHeight: 640)
    }
}

/// The grouped list of login portals, requirements and diagnostics.
struct PortalsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var probeMessage: String?
    @State private var probing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Portallar") {
                    ForEach(PortalCatalog.portals) { portal in
                        NavigationLink(value: portal) { PortalRow(portal: portal) }
                    }
                }
                Section("Gerekenler") {
                    ForEach(PortalCatalog.requirements) { requirement in
                        Label(requirement.text, systemImage: requirement.symbol)
                    }
                    Button(action: probe) {
                        HStack {
                            Label("Okuyucuyu sına", systemImage: "stethoscope")
                            Spacer()
                            if probing { ProgressView().controlSize(.small) }
                        }
                    }
                    if let probeMessage {
                        Text(probeMessage).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section { Text(PortalCatalog.footer).font(.footnote).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            .navigationTitle("e-İmza")
            .navigationDestination(for: Portal.self) { portal in
                WebPortalView(portal: portal)
            }
        }
    }

    private func probe() {
        probing = true
        Task {
            let message = await model.probeReader()
            await MainActor.run {
                probeMessage = message
                probing = false
            }
        }
    }
}

struct PortalRow: View {
    let portal: Portal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(portal.name)
            if let subtitle = portal.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .help(model.statusMessage)
    }

    private var label: String {
        switch model.cardStatus {
        case .present: return "Kart hazır"
        case .reading: return "Okunuyor"
        case .absent: return "Kart yok"
        case .error: return "Okuyucu yok"
        }
    }

    private var color: Color {
        switch model.cardStatus {
        case .present: return .green
        case .reading: return .yellow
        case .absent: return .gray
        case .error: return .red
        }
    }
}

/// A pushed WebView for one portal.
struct WebPortalView: View {
    @EnvironmentObject private var model: AppModel
    let portal: Portal

    var body: some View {
        WebContainer(url: portal.url, router: model.router)
            .navigationTitle(portal.name)
            .ignoresSafeArea(edges: .bottom)
    }
}

