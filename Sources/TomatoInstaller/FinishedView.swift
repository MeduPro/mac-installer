import SwiftUI
import TomatoCore

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
            Text("Beim ersten Start lädt tomedo noch Aktualisierungen vom Server, das kann ein paar Minuten dauern.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
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
