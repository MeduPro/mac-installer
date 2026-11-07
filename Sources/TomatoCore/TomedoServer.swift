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

/// URLs und Abfragen am tomedo-Server – dieselben Endpunkte, die tomedo und
/// Arzeko selbst für ihre Updates nutzen (übernommen aus tomi, MIT-Lizenz).
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

    /// Liefert JSON mit der Download-URL der neuesten Arzeko-Version.
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
        release.url = try release.url.replacingHost(with: address)
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

extension URL {
    /// Der Server meldet als Download-Host oft `127.0.0.1` oder einen internen Namen.
    /// Wie tomi werden Schema, Host und Port durch die bekannte Serveradresse ersetzt.
    func replacingHost(with address: ServerAddress) throws -> URL {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            throw InstallError.server("Ungültige Download-Adresse: \(absoluteString)")
        }
        c.scheme = address.scheme
        c.host = address.host
        c.port = address.port
        guard let url = c.url else { throw InstallError.server("Ungültige Download-Adresse: \(absoluteString)") }
        return url
    }
}
