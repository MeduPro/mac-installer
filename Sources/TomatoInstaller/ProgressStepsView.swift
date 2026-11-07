import SwiftUI
import TomatoCore

struct ProgressStepsView: View {
    @Environment(InstallerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(model.phase == .installing ? "Installation läuft" : "Installation nicht abgeschlossen") {
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
                        Link(destination: Brand.supportMail(subject: "Tomato-Installer: Fehler",
                                                            body: model.supportReport(error: message))) {
                            Label("Support kontaktieren (\(Brand.supportAddress))", systemImage: "envelope")
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
                ProgressView(value: progress.fraction ?? 0)
                    .progressViewStyle(.linear)
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
            if let expected = progress.expected {
                Text("\(bytes(progress.received)) von \(bytes(expected))")
            } else {
                Text(bytes(progress.received))
            }
        case .skipped(let note), .failed(let note):
            Text(note).lineLimit(1)
        default:
            EmptyView()
        }
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
