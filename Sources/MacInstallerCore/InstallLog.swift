import Foundation
import os

/// Protokoll der Installation unter `~/Library/Logs/<App-Name>.log`.
///
/// Damit lässt sich nach einem Fehlschlag nachvollziehen, was wann passiert ist –
/// auch an fremden Macs, die man nicht selbst bedient. Ohne App-Bündel (Tests) wird
/// nichts geschrieben, außer `INSTALLER_LOG` nennt eine Datei.
public enum InstallLog {
    static let dateiPraefix = "MacInstaller"

    private static let lock = OSAllocatedUnfairLock()

    public static let datei: URL? = {
        if let pfad = ProcessInfo.processInfo.environment["INSTALLER_LOG"], !pfad.isEmpty {
            return URL(filePath: pfad)
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MeduPro Installer"
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/\(name).log")
    }()

    /// Pfad für Meldungen an Menschen, mit ~ statt des Benutzerordners.
    public static var anzeigePfad: String {
        guard let datei else { return "kein Protokoll" }
        return datei.path(percentEncoded: false)
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false), with: "~/")
            .replacingOccurrences(of: "~//", with: "~/")
    }

    public static func schreiben(_ text: String) {
        guard let datei else { return }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let zeit = format.string(from: Date())
        let zeile = Data("\(zeit)  \(text)\n".utf8)
        lock.withLock {
            let fm = FileManager.default
            try? fm.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: datei.path(percentEncoded: false)) {
                fm.createFile(atPath: datei.path(percentEncoded: false), contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: datei) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: zeile)
        }
    }

    /// Kopfzeile einer Installation: App-Version, macOS, Plan.
    public static func beginn(_ plan: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        schreiben("— Installation beginnt · App \(version) · macOS \(os) · \(plan)")
    }
}
