import SwiftUI
import MacInstallerCore

struct ProgressStepsView: View {
    @Environment(InstallerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(header: header) {
                    ForEach(model.steps, id: \.self) { step in
                        StepRow(step: step, state: model.states[step] ?? .pending)
                    }
                }
                if case .failed(let message) = model.phase {
                    Section {
                        Label {
                            Text(message).textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                        if model.failedWithError {
                        Link(destination: Brand.supportMail(subject: "MeduPro Mac-Installer: Fehler",
                                                            body: model.supportReport(error: message))) {
                            Label("Support kontaktieren (\(Brand.supportAddress))", systemImage: "envelope")
                        }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Group {
                if case .failed = model.phase {
                    HStack(spacing: 12) {
                        Button("Zurück") { model.backToSetup() }
                            .controlSize(.large)
                        PrimaryButton(title: "Erneut versuchen", systemImage: "arrow.clockwise") {
                            model.retry()
                        }
                    }
                } else {
                    Button("Abbrechen", role: .cancel) { model.cancel() }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private var header: Text {
        guard model.phase == .installing else { return Text("Installation nicht abgeschlossen") }
        let current = model.steps.firstIndex { if case .running = model.states[$0] { true } else { false } }
        guard let current else { return Text("Installation läuft") }
        return Text("Installation läuft · Schritt \(current + 1) von \(model.steps.count)")
    }
}

private struct StepRow: View {
    let step: InstallStep
    let state: StepState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                icon.frame(width: 20)
                Text(step.title)
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                Spacer()
                detail.font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if case .running(let progress?) = state {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .padding(.leading, 30)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.leading, 30)
                }
                Text(status(progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
        }
        .animation(.default, value: state)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .running(let progress?):
            if let fraction = progress.fraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }
        case .running(nil):
            switch step {
            case .download: Text("Verbindung wird aufgebaut …")
            case .install: Text("wird entpackt …")
            case .configure: Text("Serveradresse wird eingetragen …")
            case .dock: Text("wird abgelegt …")
            }
        case .skipped(let note), .failed(let note):
            Text(note).lineLimit(1)
        default:
            EmptyView()
        }
    }

    /// „1,1 GB von 1,85 GB · 24 MB/s · noch ca. 1 Min.“
    private func status(_ progress: DownloadProgress) -> String {
        var parts = [progress.expected.map { "\(bytes(progress.received)) von \(bytes($0))" } ?? bytes(progress.received)]
        if let rate = progress.bytesPerSecond {
            parts.append("\(bytes(Int64(rate)))/s")
        }
        if let remaining = progress.remaining {
            switch remaining {
            case ..<10: parts.append("gleich fertig")
            case ..<60: parts.append("noch ca. \(Int((remaining / 10).rounded(.up)) * 10) Sek.")
            default: parts.append("noch ca. \(Int((remaining / 60).rounded(.up))) Min.")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
