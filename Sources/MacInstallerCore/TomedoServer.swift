import Foundation

/// Die beiden Apps, die vom tomedo-Server installiert werden können.
public enum Product: String, CaseIterable, Sendable, Codable, Identifiable {
    case tomedo
    case arzeko

    public var id: String { rawValue }
    public var displayName: String { self == .tomedo ? "tomedo" : "Arzeko" }
    public var bundleName: String { self == .tomedo ? "tomedo.app" : "Arzeko.app" }
}

public enum Architecture: String, Sendable {
    case arm, intel

    /// Prozessor des Macs – auch richtig, wenn die App unter Rosetta läuft.
    public static var current: Architecture {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1 ? .arm : .intel
    }
}

/// URLs und Abfragen am tomedo-Server. Den Archivpfad enthält die tomedo-App selbst
/// (`filebyname/serverinternal/`, `tomedo.app.tar`), die Arzeko-Abfrage baut Arzeko für
/// seine Updates genauso (`app.updater.mjs`, `get-aarch.mjs`). Quellen: docs/quellen.md.
public struct TomedoServer: Sendable {
    public let address: ServerAddress
    let session: URLSession

    public init(address: ServerAddress, session: URLSession = .shared) {
        self.address = address
        self.session = session
    }

    /// tomedo.app als tar-Archiv.
    public var tomedoArchiveURL: URL {
        address.baseURL.appending(path: "filebyname/serverinternal/tomedo.app.tar")
    }

    /// Liefert JSON mit der Download-URL der neuesten Arzeko-Version. Mit Version 0.0.0
    /// gilt jede Version auf dem Server als neuer; `aarch` ist `arm` oder `intel`.
    public func arzekoLatestURL(for arch: Architecture) -> URL {
        address.baseURL
            .appending(path: "arzeko/latestmac")
            .appending(queryItems: [
                URLQueryItem(name: "version", value: "0.0.0"),
                URLQueryItem(name: "aarch", value: arch.rawValue),
            ])
    }

    public enum CheckResult: Sendable, Equatable {
        /// Server liefert tomedo aus; Größe des Archivs, falls bekannt.
        case reachable(tomedoSize: Int64?)
        /// Server antwortet, aber nicht wie ein tomedo-Server.
        case unexpectedStatus(Int)
        case unreachable(String)
    }

    /// Prüft per HEAD-Anfrage, ob der Server tomedo ausliefert (lädt nichts herunter).
    public func check(timeout: TimeInterval = 6) async -> CheckResult {
        var request = URLRequest(url: tomedoArchiveURL, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable("Keine HTTP-Antwort") }
            guard http.statusCode == 200 else { return .unexpectedStatus(http.statusCode) }
            let length = http.expectedContentLength
            return .reachable(tomedoSize: length > 0 ? length : nil)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// Fragt ab, wo die aktuelle Arzeko-Version liegt.
    public func latestArzeko(for arch: Architecture = .current) async throws -> ArzekoRelease {
        var request = URLRequest(url: arzekoLatestURL(for: arch), timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.server("Arzeko-Version konnte nicht abgefragt werden (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        var release = try JSONDecoder().decode(ArzekoRelease.self, from: data)
        release.url = try address.resolve(release.url)
        return release
    }
}

/// Antwort von `arzeko/latestmac`.
public struct ArzekoRelease: Decodable, Sendable, Equatable {
    public var url: URL
    public var name: String
    /// SHA-512 des Zip-Archivs als Hex-Text (ältere Server liefern keinen).
    public var sha512: String?
    public var filesize: Int64?
}

extension ServerAddress {
    /// Der Server baut die Download-Adresse aus dem Host-Header der Anfrage. Hinter einer
    /// Weiterleitung (Tunnel, Proxy) zeigt sie dann z. B. auf `127.0.0.1:9901`. Pfad und
    /// Abfrage der gemeldeten Adresse bleiben, Schema, Host und Port kommen von hier.
    func resolve(_ reported: URL) throws -> URL {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.port = port
        guard let original = URLComponents(url: reported, resolvingAgainstBaseURL: false),
              !original.percentEncodedPath.isEmpty else {
            throw InstallError.server("Ungültige Download-Adresse: \(reported.absoluteString)")
        }
        parts.percentEncodedPath = original.percentEncodedPath
        parts.percentEncodedQuery = original.percentEncodedQuery
        guard let url = parts.url else {
            throw InstallError.server("Ungültige Download-Adresse: \(reported.absoluteString)")
        }
        return url
    }
}
