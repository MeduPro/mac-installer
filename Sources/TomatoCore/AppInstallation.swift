import Foundation

/// Entpacken und Ablegen einer App in `~/Applications` – tomedo lässt sich nicht
/// in `/Applications` betreiben, darum (wie bei tomi) im Benutzerordner.
public struct AppInstallation: Sendable {
    public let applicationsFolder: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        applicationsFolder = home.appending(path: "Applications", directoryHint: .isDirectory)
    }

    public func location(of product: Product) -> URL {
        applicationsFolder.appending(path: product.bundleName, directoryHint: .isDirectory)
    }

    public func isInstalled(_ product: Product) -> Bool {
        FileManager.default.fileExists(atPath: location(of: product).path(percentEncoded: false))
    }

    /// Legt `~/Applications` an (mit `.localized`, damit der Finder „Programme“ zeigt).
    public func ensureApplicationsFolder() throws {
        let fm = FileManager.default
        let path = applicationsFolder.path(percentEncoded: false)
        guard !fm.fileExists(atPath: path) else { return }
        try fm.createDirectory(at: applicationsFolder, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        fm.createFile(atPath: applicationsFolder.appending(path: ".localized").path(percentEncoded: false), contents: nil)
    }

    /// Entpackt das Archiv (tar oder zip) zuerst in einen Zwischenordner auf demselben
    /// Volume und verschiebt die App dann in einem Schritt an ihren Platz – bricht etwas
    /// ab, bleibt keine halbe App zurück.
    public func install(_ product: Product, from archive: URL) throws -> URL {
        try ensureApplicationsFolder()
        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: applicationsFolder, create: true)
        defer { try? fm.removeItem(at: staging) }

        try Self.run("/usr/bin/tar", ["-x", "-f", archive.path(percentEncoded: false),
                                      "-C", staging.path(percentEncoded: false)],
                     failure: { InstallError.archive("\(product.displayName) konnte nicht entpackt werden: \($0)") })

        guard let app = try Self.findApp(named: product.bundleName, in: staging) else {
            throw InstallError.archive("Im Archiv wurde keine \(product.bundleName) gefunden.")
        }
        let target = location(of: product)
        if fm.fileExists(atPath: target.path(percentEncoded: false)) {
            throw InstallError.archive("\(product.bundleName) ist bereits vorhanden.")
        }
        try fm.moveItem(at: app, to: target)
        return target
    }

    /// Sucht die App auf oberster Ebene oder eine Ebene tiefer (manche Archive enthalten einen Ordner).
    static func findApp(named name: String, in folder: URL) throws -> URL? {
        let fm = FileManager.default
        let top = folder.appending(path: name)
        if fm.fileExists(atPath: top.path(percentEncoded: false)) { return top }
        for sub in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) {
            let candidate = sub.appending(path: name)
            if fm.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        }
        return nil
    }

    /// Führt ein Systemprogramm aus und wirft bei Fehlern mit dessen Ausgabe.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String],
                    failure: (String) -> InstallError) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw failure(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}
