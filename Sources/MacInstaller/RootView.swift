import SwiftUI
import MacInstallerCore

struct RootView: View {
    @Environment(InstallerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .padding(.top, 18)
                .padding(.bottom, 6)

            Group {
                switch model.phase {
                case .setup:
                    SetupView()
                case .installing, .failed:
                    ProgressStepsView()
                case .finished:
                    FinishedView()
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))

            FooterView()
                .padding(.top, 16)
                .padding(.bottom, 14)
        }
        .frame(width: 560)
        .frame(minHeight: 760)
        .animation(.smooth(duration: 0.35), value: model.phase)
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Text("MeduPro Mac-Installer")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("für tomedo®")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.brand)
            Text("tomedo und Arzeko vom Server der Praxis installieren")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Herausgeber, Webseite, Support und Markenhinweis.
private struct FooterView: View {
    var body: some View {
        VStack(spacing: 6) {
            Divider().padding(.horizontal, 32).padding(.bottom, 6)
            HStack(spacing: 6) {
                Text("Ein kostenloses Angebot von **\(Brand.publisher)**")
                Text("·")
                Link("medupro.de", destination: Brand.website)
                Text("·")
                Link(Brand.supportAddress, destination: Brand.supportMail())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("tomedo® ist eine Marke der zollsoft GmbH. Der MeduPro Mac-Installer ist ein unabhängiges Projekt. Version \(Brand.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
    }
}

/// Primärer Knopf in voller Breite unten im Fenster.
struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(.brandFill)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!isEnabled)
    }
}
