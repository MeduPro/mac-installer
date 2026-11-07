import Foundation

/// Adresse eines tomedo-Servers, z. B. `192.168.1.10`, `server.praxis.local:8080`
/// oder `http://10.0.0.5:8080/tomedo_live/`.
public struct ServerAddress: Hashable, Sendable, Codable {
    public static let defaultPort = 8080
    public static let defaultPath = "/tomedo_live/"

    public var scheme: String
    public var host: String
    public var port: Int
    /// Immer mit führendem und abschließendem `/`.
    public var path: String

    public init(scheme: String = "http", host: String, port: Int = defaultPort, path: String = defaultPath) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case empty
        case invalidScheme(String)
        case invalidHost(String)
        case invalidPort(String)
        case invalidPath(String)

        public var errorDescription: String? {
            switch self {
            case .empty: "Bitte die Adresse des tomedo-Servers eingeben."
            case .invalidScheme(let s): "„\(s)“ wird nicht unterstützt – nur http oder https."
            case .invalidHost(let h): "„\(h)“ ist keine gültige Serveradresse."
            case .invalidPort(let p): "„\(p)“ ist kein gültiger Port."
            case .invalidPath(let p): "„\(p)“ ist kein gültiger Serverpfad."
            }
        }
    }

    /// Liest eine Eingabe wie `host`, `host:port`, `host:port/pfad/` oder eine vollständige URL.
    public static func parse(_ input: String) throws(ParseError) -> ServerAddress {
        var rest = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { throw .empty }

        var scheme = "http"
        if let range = rest.range(of: "://") {
            scheme = rest[..<range.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { throw .invalidScheme(scheme) }
            rest = String(rest[range.upperBound...])
        }

        var path = defaultPath
        if let slash = rest.firstIndex(of: "/") {
            let rawPath = String(rest[slash...])
            rest = String(rest[..<slash])
            if rawPath != "/" {
                path = rawPath.hasSuffix("/") ? rawPath : rawPath + "/"
            }
        }
        guard path.range(of: #"^/[A-Za-z0-9._~/-]*$"#, options: .regularExpression) != nil,
              !path.contains("//"), !path.contains("/../")
        else { throw .invalidPath(path) }

        var port = defaultPort
        var host = rest
        if let colon = rest.lastIndex(of: ":") {
            host = String(rest[..<colon])
            let rawPort = String(rest[rest.index(after: colon)...])
            guard let p = Int(rawPort), (1...65535).contains(p) else { throw .invalidPort(rawPort) }
            port = p
        }
        guard isValidHost(host) else { throw .invalidHost(host) }

        return ServerAddress(scheme: scheme, host: host.lowercased(), port: port, path: path)
    }

    /// Hostname (RFC 1123) oder IPv4-Adresse.
    static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63
                && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// Basis-URL, z. B. `http://192.168.1.10:8080/tomedo_live/`.
    public var baseURL: URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = port
        c.path = path
        return c.url!
    }

    /// Kurzform für Anzeige und Eingabefeld – Standardport und -pfad werden weggelassen.
    public var displayString: String {
        var s = scheme == "http" ? host : "\(scheme)://\(host)"
        if port != Self.defaultPort || path != Self.defaultPath { s += ":\(port)" }
        if path != Self.defaultPath { s += path }
        return s
    }
}
