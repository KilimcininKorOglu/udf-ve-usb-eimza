import SwiftUI

/// Application information. Values here are sample data, updated later.
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            headerSection
            applicationSection
            developerSection
            linksSection
            legalSection
        }
        .formStyle(.grouped)
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "signature")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("USB E-imza & UDF").font(.title2).bold()
                    Text("Nitelikli elektronik imza uygulaması")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var applicationSection: some View {
        Section("Uygulama") {
            InfoRow(title: "Sürüm", value: version)
            InfoRow(title: "Yapı", value: build)
            InfoRow(title: "Platform", value: "macOS · iOS · iPadOS")
        }
    }

    private var developerSection: some View {
        Section("Geliştirici") {
            InfoRow(title: "Ad", value: "Örnek Yazılım")
            InfoRow(title: "E-posta", value: "destek@ornek.com")
            InfoRow(title: "Konum", value: "İstanbul, Türkiye")
        }
    }

    private var linksSection: some View {
        Section("Bağlantılar") {
            Link(destination: URL(string: "https://ornek.com")!) {
                LinkRow(title: "Web sitesi", detail: "ornek.com")
            }
            Link(destination: URL(string: "https://ornek.com/gizlilik")!) {
                LinkRow(title: "Gizlilik politikası", detail: "ornek.com/gizlilik")
            }
            Link(destination: URL(string: "https://ornek.com/destek")!) {
                LinkRow(title: "Destek", detail: "ornek.com/destek")
            }
        }
    }

    private var legalSection: some View {
        Section {
            InfoRow(title: "Lisans", value: "Tescilli")
            Text("© 2026 Örnek Yazılım. Tüm hakları saklıdır.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("Yasal")
        } footer: {
            Text("Buradaki bilgiler örnek verilerdir, daha sonra güncellenecektir.")
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct LinkRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
            Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
        }
    }
}
