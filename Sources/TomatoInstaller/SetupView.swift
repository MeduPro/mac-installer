import SwiftUI
import TomatoCore

struct SetupView: View {
    @Environment(InstallerModel.self) private var model
    @FocusState private var serverFocused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Form {
                Section {
                    DiscoveredServersList()
                    TextField("Adresse", text: $model.serverInput,
                              prompt: Text("z. B. 192.168.1.10 oder server:8080"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($serverFocused)
                        .onSubmit { model.install() }
                    ServerStatusRow(check: model.serverCheck)
                } header: {
                    HStack {
                        Text("tomedo-Server")
                        Spacer()
                        if model.isDiscovering {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Erneut suchen", systemImage: "arrow.clockwise") { model.discoverServers() }
                                .buttonStyle(.borderless)
                                .labelStyle(.titleAndIcon)
                                .font(.callout)
                        }
                    }
                }

                Section("Was soll installiert werden?") {
                    HStack(spacing: 12) {
                        ChoiceCard(title: "Nur tomedo",
                                   subtitle: "Praxissoftware",
                                   symbol: "cross.case.fill",
                                   isSelected: !model.withArzeko) { model.withArzeko = false }
                        ChoiceCard(title: "tomedo + Arzeko",
                                   subtitle: "Mit Arbeitszeit und Dienstplan",
                                   symbol: "calendar.badge.clock",
                                   isSelected: model.withArzeko) { model.withArzeko = true }
                    }
                    .padding(.vertical, 4)

                    Toggle("Im Dock ablegen", isOn: $model.addToDock)

                    ForEach(model.products.filter(model.isAlreadyInstalled)) { product in
                        Label("\(product.displayName) ist schon installiert und wird übersprungen.",
                              systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            VStack(spacing: 10) {
                PrimaryButton(title: "Installieren", systemImage: "arrow.down.circle.fill",
                              isEnabled: model.canInstall) { model.install() }
                Label("Wird nach \(model.applicationsFolderPath) installiert, ohne Administrator-Passwort. Updates übernimmt tomedo danach selbst.",
                      systemImage: "lock.open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { serverFocused = true }
    }
}

/// Gefundene Server als auswählbare Zeilen.
private struct DiscoveredServersList: View {
    @Environment(InstallerModel.self) private var model

    var body: some View {
        if model.discovered.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: model.isDiscovering ? "dot.radiowaves.left.and.right" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: model.isDiscovering)
                Text(model.isDiscovering
                     ? "Suche in \(model.searchedNetworksDescription) …"
                     : model.searchedNetworks.isEmpty
                        ? "Kein Praxisnetz gefunden. Ist der Mac per WLAN oder Kabel verbunden?"
                        : "Kein tomedo-Server gefunden. Bitte die Adresse eingeben.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.callout)
        } else {
            ForEach(model.discovered) { server in
                ServerRow(server: server, isSelected: model.isSelected(server)) { model.select(server) }
            }
        }
    }
}

private struct ServerRow: View {
    let server: DiscoveredServer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.tomato : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.hostName ?? server.address.host).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.tomato : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("tomedo-Server \(server.hostName ?? server.address.host)")
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var subtitle: String {
        var parts = [server.hostName == nil ? "Port \(server.address.port)" : "\(server.address.host):\(server.address.port)"]
        if let size = server.tomedoSize {
            parts.append("tomedo \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ServerStatusRow: View {
    let check: InstallerModel.ServerCheck

    var body: some View {
        HStack(spacing: 8) {
            switch check {
            case .idle:
                Image(systemName: "network").foregroundStyle(.secondary)
                Text("Server aus der Liste wählen oder Adresse eingeben.").foregroundStyle(.secondary)
            case .invalid(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
            case .checking:
                ProgressView().controlSize(.small)
                Text("Verbindung wird geprüft …").foregroundStyle(.secondary)
            case .reachable(let size):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(size.map { "Server erreichbar, tomedo \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))" }
                     ?? "Server erreichbar")
            case .unreachable(let message):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text(message).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .animation(.default, value: check)
    }
}

private struct ChoiceCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.tomato : .secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.tomato : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.tomato.opacity(0.10) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.tomato : Color.primary.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy, value: isSelected)
    }
}
