import AppKit
import CryptoKit
import Foundation

/// Eine neuere Fassung des Installers.
public struct NeueFassung: Sendable, Equatable {
    public var version: String
    public var zip: URL
    /// SHA-256 des ZIP als Hex-Text; nil, wenn die Quelle keine angibt.
    public var sha256: String?
    /// Zusätzliche Kopfzeilen für den Download (z. B. Anmeldung).
    public var kopfzeilen: [String: String]

    public init(version: String, zip: URL, sha256: String?, kopfzeilen: [String: String] = [:]) {
        self.version = version
        self.zip = zip
        self.sha256 = sha256
        self.kopfzeilen = kopfzeilen
    }
}

/// Woher der Installer erfährt, ob es eine neuere Fassung gibt.
public protocol UpdateQuelle: Sendable {
    /// Die neueste verfügbare Fassung, oder nil, wenn die Quelle keine kennt.
    func neueste() async throws -> NeueFassung?
}

/// Prüft beim Start auf eine neuere Fassung, lädt sie, ersetzt die laufende App und
/// startet die neue. Schlägt etwas fehl, läuft die bisherige Fassung weiter.
public struct SelbstUpdate: Sendable {
    public enum Ergebnis: Sendable, Equatable {
        case aktuell
        /// Neue Fassung liegt bereit; die App muss sich beenden, die neue startet.
        case neuGestartet(version: String)
        case uebersprungen(String)
    }

    let quelle: UpdateQuelle
    let laufend: String
    let app: URL
    let bundleID: String?

    public init(quelle: UpdateQuelle, laufend: String? = nil, app: URL = Bundle.main.bundleURL,
                bundleID: String? = Bundle.main.bundleIdentifier) {
        self.quelle = quelle
        self.laufend = laufend
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        self.app = app
        self.bundleID = bundleID
    }

    /// Ob eine Prüfung überhaupt sinnvoll ist: nur in einem gebauten App-Bündel mit echter Version.
    public var moeglich: Bool {
        app.pathExtension == "app" && Self.versionsteile(laufend) != nil
            && ProcessInfo.processInfo.environment["INSTALLER_KEIN_UPDATE"] == nil
    }

    /// Fragt die Quelle; nil, wenn es nichts Neueres gibt.
    public func pruefen() async throws -> NeueFassung? {
        guard moeglich else { return nil }
        guard let neu = try await quelle.neueste() else { return nil }
        return Self.neuer(neu.version, als: laufend) ? neu : nil
    }

    /// Lädt `neu`, prüft es, legt es an die Stelle der laufenden App und startet es.
    public func einspielen(_ neu: NeueFassung,
                           fortschritt: @escaping @Sendable (DownloadProgress) -> Void) async throws -> Ergebnis {
        InstallLog.schreiben("Selbstaktualisierung \(laufend) → \(neu.version): Download \(neu.zip.absoluteString)")
        let zip = try await Downloader().download(neu.zip, kopfzeilen: neu.kopfzeilen, progress: fortschritt)
        defer { try? FileManager.default.removeItem(at: zip) }

        if let erwartet = neu.sha256?.lowercased(), !erwartet.isEmpty {
            guard try Self.sha256(of: zip) == erwartet else {
                throw InstallError.checksumMismatch("Installer \(neu.version)")
            }
        }

        let fm = FileManager.default
        let entpackt = fm.temporaryDirectory.appending(path: "\(InstallLog.dateiPraefix)-Update-\(UUID().uuidString)")
        try fm.createDirectory(at: entpackt, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: entpackt) }
        try Self.ausfuehren("/usr/bin/ditto", ["-x", "-k", zip.path(percentEncoded: false), entpackt.path(percentEncoded: false)])

        guard let neueApp = try fm.contentsOfDirectory(at: entpackt, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.archive("Im Update-Paket fehlt die App.")
        }
        let info = Bundle(url: neueApp)
        guard info?.bundleIdentifier == bundleID else {
            throw InstallError.archive("Das Update-Paket enthält eine andere App (\(info?.bundleIdentifier ?? "?")).")
        }
        let version = info?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard version == neu.version else {
            throw InstallError.archive("Das Update-Paket hat Version \(version) statt \(neu.version).")
        }

        let ziel = try ablegen(neueApp)
        InstallLog.schreiben("Selbstaktualisierung: \(neu.version) liegt unter \(ziel.path(percentEncoded: false)), Neustart")
        let konfig = NSWorkspace.OpenConfiguration()
        konfig.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: ziel, configuration: konfig)
        return .neuGestartet(version: neu.version)
    }

    /// Ersetzt die laufende App, wenn ihr Ordner beschreibbar ist (Programme, Downloads).
    /// Läuft sie von einem Disk-Image oder ohne Schreibrecht, liegt die neue Fassung unter
    /// `~/Library/Application Support/<Name>/`.
    func ablegen(_ neueApp: URL) throws -> URL {
        let fm = FileManager.default
        let ordner = app.deletingLastPathComponent()
        if fm.isWritableFile(atPath: ordner.path(percentEncoded: false)),
           fm.isWritableFile(atPath: app.path(percentEncoded: false)) {
            let alt = fm.temporaryDirectory.appending(path: "\(InstallLog.dateiPraefix)-alt-\(UUID().uuidString).app")
            do {
                try fm.moveItem(at: app, to: alt)
                do {
                    try fm.copyItem(at: neueApp, to: app)
                    try? fm.removeItem(at: alt)
                    return app
                } catch {
                    try? fm.moveItem(at: alt, to: app)
                    throw error
                }
            } catch {
                InstallLog.schreiben("Selbstaktualisierung: Ersetzen an Ort und Stelle ging nicht (\(error.localizedDescription))")
            }
        }
        let name = app.lastPathComponent
        let ablage = fm.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/\(app.deletingPathExtension().lastPathComponent)")
        try fm.createDirectory(at: ablage, withIntermediateDirectories: true)
        let ziel = ablage.appending(path: name)
        if fm.fileExists(atPath: ziel.path(percentEncoded: false)) { try fm.removeItem(at: ziel) }
        try fm.copyItem(at: neueApp, to: ziel)
        return ziel
    }

    // MARK: Hilfen

    /// "1.0.10" → [1, 0, 10]; ein führendes "v" ist erlaubt.
    public static func versionsteile(_ text: String) -> [Int]? {
        let rein = text.trimmingCharacters(in: .whitespaces).trimmingPrefix("v")
        let teile = rein.split(separator: ".").map { Int($0) }
        guard !teile.isEmpty, teile.allSatisfy({ $0 != nil }) else { return nil }
        return teile.compactMap { $0 }
    }

    public static func neuer(_ kandidat: String, als laufend: String) -> Bool {
        guard let a = versionsteile(kandidat), let b = versionsteile(laufend) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func ausfuehren(_ programm: String, _ argumente: [String]) throws {
        let p = Process()
        p.executableURL = URL(filePath: programm)
        p.arguments = argumente
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw InstallError.archive("\(URL(filePath: programm).lastPathComponent) endete mit \(p.terminationStatus).")
        }
    }
}
