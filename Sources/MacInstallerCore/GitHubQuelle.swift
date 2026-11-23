import Foundation

/// Neueste Fassung aus den GitHub-Releases des öffentlichen Repos.
///
/// Erwartet je Release ein ZIP mit der App und eine `.sha256`-Datei im Format von
/// `shasum -a 256` (so baut sie `scripts/build-app.sh`). Ohne passende Prüfsumme wird
/// nicht aktualisiert.
public struct GitHubQuelle: UpdateQuelle {
    public let repo: String
    let session: URLSession

    public init(repo: String, session: URLSession = .shared) {
        self.repo = repo
        self.session = session
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    public func neueste() async throws -> NeueFassung? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (daten, antwort) = try await session.data(for: request)
        guard (antwort as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let release = try JSONDecoder().decode(Release.self, from: daten)
        guard !release.draft, !release.prerelease,
              let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let pruef = release.assets.first(where: { $0.name.hasSuffix(".sha256") }) else { return nil }

        let (text, pruefAntwort) = try await session.data(from: pruef.browser_download_url)
        guard (pruefAntwort as? HTTPURLResponse)?.statusCode == 200,
              let summe = Self.summe(fuer: zip.name, in: String(decoding: text, as: UTF8.self)) else { return nil }
        let version = String(release.tag_name.trimmingPrefix("v"))
        return NeueFassung(version: version, zip: zip.browser_download_url, sha256: summe)
    }

    /// Zeile `<hex>  <datei>` aus einer shasum-Ausgabe.
    static func summe(fuer datei: String, in text: String) -> String? {
        for zeile in text.split(whereSeparator: \.isNewline) {
            let teile = zeile.split(separator: " ", omittingEmptySubsequences: true)
            if teile.count == 2, teile[1].trimmingPrefix("*") == datei, teile[0].count == 64 {
                return teile[0].lowercased()
            }
        }
        return nil
    }
}
