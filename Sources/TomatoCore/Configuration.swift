import Foundation

/// Trägt den tomedo-Server ein, damit tomedo beim ersten Start nicht danach fragt.
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

/// Erzeugt `~/Library/Application Support/Arzeko/usersetting.json` mit der
/// Serveradresse – Vorlage und Standardwerte aus tomi (MIT-Lizenz).
public struct ArzekoSettings: Encodable, Equatable {
    var protocol_: String
    var authPassword = "tomedo"
    var xApiKey = "tomedo"
    var ipAddress: String
    var oneWaySSLPort = 9444
    var authPortServerTools = 9442
    var authPort = 9443
    var httpsPort = 8443
    var httpPort: Int
    var basePath: String
    var autoUpdatePath = "arzeko/latestmac?version="
    var calendarOptions = CalendarOptions()
    var exportOptions = ExportOptions()
    var timezone = 1
    var disableUpdates = false
    var logLevel = "info"

    struct CalendarOptions: Encodable, Equatable {
        var weekNumbers = true
        var dayMaxEvents = 5
        var minTime = "06:00:00"
        var maxTime = "23:00:00"
        var printSorting = "start,title"
        var snapDuration = "00:15:00"
        var slotDuration = "00:30:00"
        var allDaySlot = true
        var showNamesMonth = false
        var eventLimitWeek = 5
        var showNamesInsteadOfKuerzel = true
        var selectable = true
        var restorePosition = false
        var showAbwesenMonth = false
        var hiddenDays: [Int] = []
        var showNutzerSchichtzeiten = true
        var showPopovers = true
        var pauseDuration = 0
    }

    struct ExportOptions: Encodable, Equatable {
        var abwesenExport = false
        var eigeneSchichtenOnly = false
    }

    enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol"
        case authPassword, xApiKey, ipAddress, oneWaySSLPort, authPortServerTools, authPort,
             httpsPort, httpPort, basePath, autoUpdatePath, calendarOptions, exportOptions,
             timezone, disableUpdates, logLevel
    }

    public init(server: ServerAddress) {
        protocol_ = server.scheme
        ipAddress = server.host
        httpPort = server.port
        basePath = server.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func configFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/Arzeko/usersetting.json")
    }

    /// Schreibt die Datei (wie tomi: eine vorhandene wird ersetzt, damit der neue Server gilt).
    public func write(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let file = Self.configFile(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try jsonData().write(to: file, options: .atomic)
    }
}
