import AppKit
import Observation
import MacInstallerCore

/// Zustand der App: Eingaben, Serverprüfung und Ablauf der Installation.
@MainActor @Observable
final class InstallerModel {
    enum Phase: Equatable {
        case setup
        case installing
        case finished
        case failed(String)
    }

    enum ServerCheck: Equatable {
        case idle
        case invalid(String)
        case checking
        case reachable(tomedoSize: Int64?)
        case unreachable(String)
    }

    // MARK: Eingaben – bleiben über Neustarts erhalten

    var serverInput: String {
        didSet {
            guard serverInput != oldValue else { return }
            defaults.set(serverInput, forKey: Keys.server)
            scheduleServerCheck()
        }
    }
    var withArzeko: Bool { didSet { defaults.set(withArzeko, forKey: Keys.arzeko) } }
    var addToDock: Bool { didSet { defaults.set(addToDock, forKey: Keys.dock) } }

    // MARK: Zustand

    private(set) var serverCheck: ServerCheck = .idle
    private(set) var discovered: [DiscoveredServer] = []
    private(set) var isDiscovering = false
    private(set) var searchedNetworks: [LocalNetwork] = []
    private var discoveryTask: Task<Void, Never>?
    private(set) var phase: Phase = .setup
    private(set) var steps: [InstallStep] = []
    private(set) var states: [InstallStep: StepState] = [:]
    private(set) var installed: [Product: URL] = [:]

    private let defaults: UserDefaults
    private var checkTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private let installation = AppInstallation()

    private enum Keys {
        static let server = "server"
        static let arzeko = "withArzeko"
        static let dock = "addToDock"
    }

    /// Vorführmodus für Bildschirmfotos (`MACINSTALLER_DEMO=1`): Beispielserver, keine Netzabfragen,
    /// Eingaben landen in einem eigenen, beim Start geleerten Einstellungsbereich.
    private let isDemo = ProcessInfo.processInfo.environment["MACINSTALLER_DEMO"] == "1"

    init(defaults: UserDefaults = .standard) {
        let defaults = isDemo ? Self.demoDefaults() : defaults
        self.defaults = defaults
        serverInput = defaults.string(forKey: Keys.server) ?? ""
        withArzeko = defaults.bool(forKey: Keys.arzeko)
        addToDock = defaults.object(forKey: Keys.dock) as? Bool ?? true
        if isDemo {
            showDemo()
            return
        }
        scheduleServerCheck(delay: .zero)
        discoverServers()
    }

    private static func demoDefaults() -> UserDefaults {
        let suite = "de.medupro.mac-installer.demo"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private func showDemo() {
        let size: Int64 = 1_850_000_000
        discovered = [
            DiscoveredServer(address: ServerAddress(host: "192.168.1.10"), hostName: "tomedo-server.local", tomedoSize: size),
            DiscoveredServer(address: ServerAddress(host: "192.168.1.20"), hostName: "tomedo-test.local", tomedoSize: size),
        ]
        searchedNetworks = [LocalNetwork(address: 0xC0A8_01D5, prefixLength: 24)]
        isDiscovering = false
        withArzeko = true
        addToDock = true
        serverInput = discovered[0].address.displayString
        serverCheck = .reachable(tomedoSize: size)
    }

    // MARK: Serversuche im Netz

    /// Durchsucht das Praxisnetz nach tomedo-Servern. Ist noch keine Adresse gewählt
    /// und genau ein Server da, wird er übernommen.
    func discoverServers() {
        guard !isDemo else { return }
        discoveryTask?.cancel()
        discovered = []
        searchedNetworks = LocalNetwork.current() + Self.extraNetworks()
        isDiscovering = true
        discoveryTask = Task {
            for await server in ServerDiscovery().discover(in: searchedNetworks) {
                discovered.append(server)
                discovered.sort { $0.address.host.localizedStandardCompare($1.address.host) == .orderedAscending }
            }
            guard !Task.isCancelled else { return }
            isDiscovering = false
            if serverInput.isEmpty, discovered.count == 1 { select(discovered[0]) }
        }
    }

    /// Für Tests außerhalb des Praxisnetzes: `MACINSTALLER_EXTRA_NETWORKS=192.168.10.0/24`.
    private static func extraNetworks() -> [LocalNetwork] {
        let value = ProcessInfo.processInfo.environment["MACINSTALLER_EXTRA_NETWORKS"] ?? ""
        return value.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: "/")
            let octets = parts.first?.split(separator: ".").compactMap { UInt32($0) } ?? []
            guard octets.count == 4, parts.count == 2, let prefix = Int(parts[1]), (22...30).contains(prefix) else { return nil }
            return LocalNetwork(address: octets.reduce(0) { $0 << 8 | $1 }, prefixLength: prefix)
        }
    }

    func select(_ server: DiscoveredServer) {
        serverInput = server.address.displayString
    }

    func isSelected(_ server: DiscoveredServer) -> Bool {
        parsedServer == server.address
    }

    var searchedNetworksDescription: String {
        searchedNetworks.map(\.description).joined(separator: ", ")
    }

    var products: [Product] { withArzeko ? [.tomedo, .arzeko] : [.tomedo] }

    var parsedServer: ServerAddress? { try? ServerAddress.parse(serverInput) }

    var canInstall: Bool {
        if case .reachable = serverCheck, phase == .setup { return true }
        return false
    }

    func isAlreadyInstalled(_ product: Product) -> Bool { installation.isInstalled(product) }

    var applicationsFolderPath: String {
        (installation.applicationsFolder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Serverprüfung

    /// Prüft die Adresse kurz nach der letzten Eingabe.
    func scheduleServerCheck(delay: Duration = .milliseconds(600)) {
        guard !isDemo else { return }
        checkTask?.cancel()
        let input = serverInput
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else {
            serverCheck = .idle
            return
        }
        let address: ServerAddress
        do {
            address = try ServerAddress.parse(input)
        } catch {
            serverCheck = .invalid(error.localizedDescription)
            return
        }
        serverCheck = .checking
        checkTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await TomedoServer(address: address).check()
            guard !Task.isCancelled else { return }
            switch result {
            case .reachable(let size):
                serverCheck = .reachable(tomedoSize: size)
            case .unexpectedStatus(let code):
                serverCheck = .unreachable("Der Server antwortet, liefert aber kein tomedo aus (HTTP \(code)). Stimmen Port und Pfad?")
            case .unreachable(let message):
                serverCheck = .unreachable(message + " Hat macOS nach dem lokalen Netzwerk gefragt? Dann unter Systemeinstellungen › Datenschutz & Sicherheit › Lokales Netzwerk erlauben.")
            }
        }
    }

    // MARK: Installation

    func install() {
        guard canInstall, let server = parsedServer else { return }
        let plan = InstallPlan(server: server, products: products, addToDock: addToDock)
        steps = plan.steps
        states = Dictionary(uniqueKeysWithValues: steps.map { ($0, .pending) })
        installed = [:]
        phase = .installing

        // Meldungen kommen aus Hintergrund-Threads – der Stream hält ihre Reihenfolge.
        let (events, continuation) = AsyncStream.makeStream(of: (InstallStep, StepState).self)
        let installer = Installer(plan: plan)

        installTask = Task {
            let consumer = Task { @MainActor in
                for await (step, state) in events { self.states[step] = state }
            }
            do {
                let result = try await installer.run { continuation.yield(($0, $1)) }
                continuation.finish()
                await consumer.value
                installed = result
                phase = .finished
            } catch {
                continuation.finish()
                await consumer.value
                let message = (error as? InstallError) == .cancelled || error is CancellationError
                    ? "Die Installation wurde abgebrochen."
                    : error.localizedDescription
                for (step, state) in states where state == .pending || isRunning(state) {
                    states[step] = isRunning(state) ? .failed("abgebrochen") : .pending
                }
                phase = .failed(message)
            }
        }
    }

    func cancel() { installTask?.cancel() }

    /// Prüft den Server neu und startet die Installation, wenn er erreichbar ist.
    func retry() {
        guard let server = parsedServer else { return backToSetup() }
        checkTask?.cancel()
        serverCheck = .checking
        Task {
            if case .reachable(let size) = await TomedoServer(address: server).check() {
                serverCheck = .reachable(tomedoSize: size)
                phase = .setup
                install()
            } else {
                backToSetup()
            }
        }
    }

    /// Text für die Support-Mail – ohne persönliche Daten außer der Serveradresse.
    func supportReport(error: String) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let lines = [
            "Hallo MeduPro-Support,", "",
            "beim MeduPro Mac-Installer ist ein Fehler aufgetreten:", error, "",
            "Version: \(Brand.version)",
            "macOS: \(os) (\(Architecture.current.rawValue))",
            "Server: \(parsedServer?.baseURL.absoluteString ?? serverInput)",
            "Auswahl: \(products.map(\.displayName).joined(separator: " + "))",
            "Schritte:",
        ] + steps.map { "  \($0.title): \(String(describing: states[$0] ?? .pending))" }
        return lines.joined(separator: "\n")
    }

    func backToSetup() {
        phase = .setup
        scheduleServerCheck(delay: .zero)
    }

    func open(_ product: Product) {
        guard let url = installed[product] else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func revealApplicationsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting(Array(installed.values))
    }

    private func isRunning(_ state: StepState) -> Bool {
        if case .running = state { return true }
        return false
    }
}
