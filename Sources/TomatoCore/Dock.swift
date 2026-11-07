import Foundation

/// Legt Apps im Dock ab, ohne vorhandene Einträge anzufassen.
public enum Dock {
    static var domain: CFString { "com.apple.dock" as CFString }
    static var key: CFString { "persistent-apps" as CFString }

    /// Eintrag in `persistent-apps`, wie ihn das Dock selbst anlegt.
    static func tile(for app: URL) -> [String: Any] {
        ["tile-data": ["file-data": ["_CFURLString": app.absoluteString, "_CFURLStringType": 15]]]
    }

    static func contains(_ app: URL, in tiles: [[String: Any]]) -> Bool {
        let wanted = app.standardizedFileURL.path(percentEncoded: false)
        return tiles.contains { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String,
                  let url = URL(string: string) else { return false }
            return url.standardizedFileURL.path(percentEncoded: false) == wanted
        }
    }

    /// Fügt die Apps hinten an und startet das Dock neu, falls sich etwas geändert hat.
    /// - Returns: die tatsächlich hinzugefügten Apps.
    @discardableResult
    public static func add(_ apps: [URL]) -> [URL] {
        var tiles = (CFPreferencesCopyAppValue(key, domain) as? [[String: Any]]) ?? []
        let added = apps.filter { !contains($0, in: tiles) }
        guard !added.isEmpty else { return [] }
        tiles += added.map(tile(for:))
        CFPreferencesSetAppValue(key, tiles as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        _ = try? AppInstallation.run("/usr/bin/killall", ["Dock"], failure: { _ in .cancelled })
        return added
    }
}
