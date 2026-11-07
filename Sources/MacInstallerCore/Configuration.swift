import Foundation

/// Trägt den tomedo-Server ein, damit tomedo beim ersten Start nicht danach fragt.
/// Domäne und Schlüssel stehen so in der tomedo-App und in Arzekos `user.setting.mjs`,
/// das die Adresse von dort liest (docs/quellen.md).
public enum TomedoConfiguration {
    public static var domain: CFString { "com.zollsoft.tomedo-macOS" as CFString }
    public static var serverKey: CFString { "ZS_ServerAdress" as CFString }   // Schreibweise so von tomedo

    public static func setServer(_ address: ServerAddress) throws {
        CFPreferencesSetAppValue(serverKey, address.baseURL.absoluteString as CFString, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            throw InstallError.configuration("Die tomedo-Einstellungen konnten nicht gespeichert werden.")
        }
    }

    public static func currentServer() -> String? {
        CFPreferencesCopyAppValue(serverKey, domain) as? String
    }
}

/// Trägt den tomedo-Server in Arzekos `usersetting.json` ein.
///
/// Arzeko (geprüft mit 1.171.0, `main-process/settings/user.setting.mjs`) ergänzt beim Start
/// jeden fehlenden Schlüssel selbst mit seinen Standardwerten. Deshalb schreibt diese App nur
/// die Verbindungsangaben – in der Form, die Arzeko selbst aus einer tomedo-Serveradresse
/// bildet: `protocol`, `ipAddress`, `<protocol>Port` und `basePath`. Alle übrigen Einstellungen
/// einer vorhandenen Datei (Kalender, Export, Ports) bleiben unverändert. Quellen: docs/quellen.md.
public struct ArzekoConnection: Equatable {
    public let server: ServerAddress

    public init(server: ServerAddress) {
        self.server = server
    }

    public static func configFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/Arzeko/usersetting.json")
    }

    /// Die vier Verbindungsangaben, die Arzeko aus einer Serveradresse ableitet.
    var entries: [String: Any] {
        let basePath = server.path.split(separator: "/").first.map(String.init) ?? ""
        return [
            "protocol": server.scheme,
            "ipAddress": server.host,
            "\(server.scheme)Port": server.port,
            "basePath": basePath,
        ]
    }

    /// Setzt die Verbindungsangaben in `existing` (Inhalt einer vorhandenen Datei oder leer).
    func merged(into existing: [String: Any]) -> [String: Any] {
        existing.merging(entries) { _, new in new }
    }

    public func jsonData(existing: [String: Any] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: merged(into: existing),
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Liest eine vorhandene Datei, setzt den Server und schreibt sie zurück; legt sie sonst an.
    /// Eine unlesbare Datei wird ersetzt, Arzeko ergänzt die fehlenden Werte beim nächsten Start.
    public func write(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let file = Self.configFile(home: home)
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = object
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try jsonData(existing: existing).write(to: file, options: .atomic)
    }
}
