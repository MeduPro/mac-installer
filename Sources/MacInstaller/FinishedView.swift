import SwiftUI
import MacInstallerCore

struct FinishedView: View {
    @Environment(InstallerModel.self) private var model
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
            Text(model.installed.count > 1 ? "tomedo und Arzeko sind bereit" : "tomedo ist bereit")
                .font(.title2.bold())
            Text("Beim ersten Start von tomedo unter Einstellungen › Arbeitsplatz › Grundeinstellungen den Arbeitsplatz auswählen oder anlegen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            if let folder = model.installed[.tomedo]?.deletingLastPathComponent() {
                VStack(spacing: 4) {
                    Text(model.usesUserApplicationsFolder ? "Installiert in „Programme“ in Ihrem Benutzerordner:" : "Installiert in:")
                        .font(.callout)
                    Text(folder.path(percentEncoded: false))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            }
            Button("Im Finder zeigen") { model.revealApplicationsFolder() }
                .buttonStyle(.link)
            Spacer()

            HStack(spacing: 12) {
                if model.installed[.arzeko] != nil {
                    Button("Arzeko öffnen") { model.open(.arzeko) }
                        .controlSize(.large)
                }
                PrimaryButton(title: "tomedo öffnen", systemImage: "arrow.up.forward.app.fill") {
                    model.open(.tomedo)
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 32)
        }
        .onAppear { appeared = true }
    }
}
