import Foundation
import os

/// Ein sichtbarer Schritt der Installation.
public enum InstallStep: Hashable, Sendable {
    case download(Product)
    case install(Product)
    case configure(Product)
    case dock

    public var title: String {
        switch self {
        case .download(let p): "\(p.displayName) herunterladen"
        case .install(let p): "\(p.displayName) installieren"
        case .configure(let p): "\(p.displayName) mit dem Server verbinden"
        case .dock: "Im Dock ablegen"
        }
    }
}

public enum StepState: Equatable, Sendable {
    case pending
    case running(DownloadProgress?)
    case done
    case skipped(String)
    case failed(String)
}

public struct InstallPlan: Sendable, Equatable {
    public var server: ServerAddress
    public var products: [Product]
    public var addToDock: Bool

    public init(server: ServerAddress, products: [Product], addToDock: Bool) {
        self.server = server
        self.products = products
        self.addToDock = addToDock
    }

    public var steps: [InstallStep] {
        products.flatMap { [.download($0), .install($0), .configure($0)] } + (addToDock ? [.dock] : [])
    }
}

/// Führt die Installation aus und meldet jeden Schrittwechsel.
public struct Installer: Sendable {
    public typealias Report = @Sendable (InstallStep, StepState) -> Void

    let plan: InstallPlan
    let installation: AppInstallation
    let home: URL
    let downloader = Downloader()
    let log = Logger(subsystem: "de.medupro.mac-installer", category: "install")

    public init(plan: InstallPlan, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.plan = plan
        self.home = home
        installation = AppInstallation(home: home)
    }

    /// - Returns: Orte der installierten bzw. bereits vorhandenen Apps.
    @discardableResult
    public func run(report: @escaping Report) async throws -> [Product: URL] {
        let server = TomedoServer(address: plan.server)
        var installed: [Product: URL] = [:]
        var newlyInstalled: [URL] = []

        for product in plan.products {
            let target = installation.location(of: product)
            if installation.isInstalled(product) {
                // Vorhandene Apps bleiben unangetastet – sie aktualisieren sich selbst.
                let note = "bereits installiert"
                report(.download(product), .skipped(note))
                report(.install(product), .skipped(note))
                report(.configure(product), .skipped(note))
                installed[product] = target
                log.info("\(product.bundleName, privacy: .public) bereits vorhanden, übersprungen")
                continue
            }
            try Task.checkCancellation()

            // 1. Herunterladen
            report(.download(product), .running(nil))
            let archive: URL
            do {
                archive = try await download(product, from: server) { report(.download(product), .running($0)) }
            } catch {
                report(.download(product), .failed(error.localizedDescription))
                throw error
            }
            defer { try? FileManager.default.removeItem(at: archive) }
            report(.download(product), .done)
            try Task.checkCancellation()

            // 2. Installieren
            report(.install(product), .running(nil))
            do {
                installed[product] = try installation.install(product, from: archive)
                newlyInstalled.append(target)
            } catch {
                report(.install(product), .failed(error.localizedDescription))
                throw error
            }
            report(.install(product), .done)

            // 3. Server eintragen
            report(.configure(product), .running(nil))
            do {
                switch product {
                case .tomedo: try TomedoConfiguration.setServer(plan.server)
                case .arzeko: try ArzekoConnection(server: plan.server).write(home: home)
                }
            } catch {
                report(.configure(product), .failed(error.localizedDescription))
                throw error
            }
            report(.configure(product), .done)
            log.info("\(product.bundleName, privacy: .public) installiert")
        }

        if plan.addToDock {
            report(.dock, .running(nil))
            let added = Dock.add(plan.products.compactMap { installed[$0] })
            report(.dock, added.isEmpty ? .skipped("schon im Dock") : .done)
        }
        return installed
    }

    private func download(_ product: Product, from server: TomedoServer,
                          progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        switch product {
        case .tomedo:
            return try await downloader.download(server.tomedoArchiveURL, progress: progress)
        case .arzeko:
            let release = try await server.latestArzeko()
            let file = try await downloader.download(release.url, expectedSize: release.filesize, progress: progress)
            if let expected = release.sha512?.lowercased(), !expected.isEmpty {
                guard try Downloader.sha512(of: file) == expected else {
                    try? FileManager.default.removeItem(at: file)
                    throw InstallError.checksumMismatch("Arzeko \(release.name)")
                }
            }
            return file
        }
    }
}
