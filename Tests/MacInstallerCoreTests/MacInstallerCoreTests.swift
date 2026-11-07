import Foundation
import Testing
@testable import MacInstallerCore

@Suite("Serveradresse")
struct ServerAddressTests {
    @Test("Kurzformen werden ergänzt", arguments: [
        ("192.168.1.10", "http://192.168.1.10:8080/tomedo_live/"),
        ("  server.praxis.local  ", "http://server.praxis.local:8080/tomedo_live/"),
        ("10.0.0.5:9090", "http://10.0.0.5:9090/tomedo_live/"),
        ("10.0.0.5:8080/tomedo_test", "http://10.0.0.5:8080/tomedo_test/"),
        ("http://Server:8080/tomedo_live/", "http://server:8080/tomedo_live/"),
        ("https://tomedo.example.de:8443/", "https://tomedo.example.de:8443/tomedo_live/"),
    ])
    func parses(input: String, expected: String) throws {
        #expect(try ServerAddress.parse(input).baseURL.absoluteString == expected)
    }

    @Test("Ungültige Eingaben werden abgelehnt", arguments: [
        "", "   ", "ftp://server", "a;rm -rf", "server:0", "server:70000", "server:abc",
        "-server", "ser ver", "server/../etc", "server//x", "srv/<script>",
    ])
    func rejects(input: String) {
        #expect(throws: ServerAddress.ParseError.self) { try ServerAddress.parse(input) }
    }

    @Test func displayStringRoundTrip() throws {
        for input in ["192.168.1.10", "srv:9090", "srv:8080/other/", "https://srv:8443"] {
            let address = try ServerAddress.parse(input)
            #expect(try ServerAddress.parse(address.displayString) == address)
        }
        #expect(try ServerAddress.parse("http://srv:8080/tomedo_live/").displayString == "srv")
    }
}

@Suite("tomedo-Server")
struct TomedoServerTests {
    let server = TomedoServer(address: ServerAddress(host: "192.168.1.10"))

    @Test func tomedoArchiveURL() {
        #expect(server.tomedoArchiveURL.absoluteString
                == "http://192.168.1.10:8080/tomedo_live/filebyname/serverinternal/tomedo.app.tar")
    }

    @Test func arzekoLatestURL() {
        #expect(server.arzekoLatestURL(for: .arm).absoluteString
                == "http://192.168.1.10:8080/tomedo_live/arzeko/latestmac?version=0.0.0&aarch=arm")
        #expect(server.arzekoLatestURL(for: .intel).absoluteString.hasSuffix("aarch=intel"))
    }

    @Test("Arzeko-Antwort: Host wird durch die Serveradresse ersetzt")
    func decodesArzekoRelease() throws {
        // Echte Antwort eines tomedo-Servers (gekürzt).
        let json = #"""
        {"url":"http://127.0.0.1:9901/resteasy/tomedo_live/filebyname/serverinternalzip/arzeko/Arzeko-1.171.0-mac-arm.zip",
         "name":"1.171.0","notes":"Aarch: arm","pub_date":null,"sha512":"94f3ab","filesize":101627742}
        """#
        var release = try JSONDecoder().decode(ArzekoRelease.self, from: Data(json.utf8))
        release.url = try server.address.resolve(release.url)
        #expect(release.url.absoluteString
                == "http://192.168.1.10:8080/resteasy/tomedo_live/filebyname/serverinternalzip/arzeko/Arzeko-1.171.0-mac-arm.zip")
        #expect(release.name == "1.171.0")
        #expect(release.filesize == 101_627_742)
    }

    @Test("Ältere Server ohne Prüfsumme")
    func decodesMinimalRelease() throws {
        let json = #"{"url":"http://localhost/x/Arzeko.zip","name":"1.0"}"#
        let release = try JSONDecoder().decode(ArzekoRelease.self, from: Data(json.utf8))
        #expect(release.sha512 == nil)
    }
}

@Suite("Konfiguration")
struct ConfigurationTests {
    @Test("Neue Arzeko-Einstellungen enthalten nur die Verbindung, wie Arzeko sie bildet")
    func arzekoConnectionOnly() throws {
        let connection = ArzekoConnection(server: try ServerAddress.parse("10.0.0.5:8080/tomedo_live/"))
        let object = try JSONSerialization.jsonObject(with: connection.jsonData()) as! [String: Any]
        #expect(Set(object.keys) == ["protocol", "ipAddress", "httpPort", "basePath"])
        #expect(object["protocol"] as? String == "http")
        #expect(object["ipAddress"] as? String == "10.0.0.5")
        #expect(object["httpPort"] as? Int == 8080)
        #expect(object["basePath"] as? String == "tomedo_live")
    }

    @Test("https setzt httpsPort")
    func arzekoConnectionHTTPS() throws {
        let connection = ArzekoConnection(server: try ServerAddress.parse("https://tomedo.praxis.de:8443"))
        let object = try JSONSerialization.jsonObject(with: connection.jsonData()) as! [String: Any]
        #expect(object["httpsPort"] as? Int == 8443)
        #expect(object["httpPort"] == nil)
    }

    @Test("Vorhandene Einstellungen bleiben, nur der Server ändert sich")
    func arzekoConnectionKeepsSettings() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = ArzekoConnection.configFile(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let before = #"{"protocol":"http","ipAddress":"a","httpPort":8080,"basePath":"tomedo_live","logLevel":"debug","calendarOptions":{"minTime":"07:00:00"}}"#
        try Data(before.utf8).write(to: file)

        try ArzekoConnection(server: ServerAddress(host: "b", port: 9090)).write(home: home)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(object["ipAddress"] as? String == "b")
        #expect(object["httpPort"] as? Int == 9090)
        #expect(object["logLevel"] as? String == "debug")
        #expect((object["calendarOptions"] as? [String: Any])?["minTime"] as? String == "07:00:00")
    }

    @Test("Unlesbare Datei wird ersetzt")
    func arzekoConnectionReplacesBrokenFile() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = ArzekoConnection.configFile(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kein json".utf8).write(to: file)
        try ArzekoConnection(server: ServerAddress(host: "c")).write(home: home)
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains(#""ipAddress" : "c""#))
    }

    @Test func dockTileDetection() {
        let app = URL(filePath: "/Users/x/Applications/tomedo.app", directoryHint: .isDirectory)
        let tiles = [Dock.tile(for: app)]
        #expect(tiles[0]["tile-type"] as? String == "file-tile")
        #expect(Dock.contains(app, in: tiles))
        #expect(!Dock.contains(URL(filePath: "/Users/x/Applications/Arzeko.app"), in: tiles))
        #expect((tiles[0]["tile-data"] as? [String: Any]).flatMap { $0["file-data"] as? [String: Any] }?["_CFURLString"] as? String
                == "file:///Users/x/Applications/tomedo.app/")
    }
}

@Suite("Installation")
struct InstallationTests {
    @Test("Archiv entpacken und atomar ablegen")
    func installsFromTar() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: work) }
        let source = work.appending(path: "src")
        try fm.createDirectory(at: source.appending(path: "tomedo.app/Contents"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appending(path: "tomedo.app/Contents/Info.plist"))
        let archive = work.appending(path: "tomedo.app.tar")
        try AppInstallation.run("/usr/bin/tar", ["-c", "-f", archive.path(percentEncoded: false),
                                                 "-C", source.path(percentEncoded: false), "tomedo.app"],
                                failure: { InstallError.archive($0) })

        let home = work.appending(path: "home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let installation = AppInstallation(home: home)
        #expect(!installation.isInstalled(.tomedo))
        let target = try installation.install(.tomedo, from: archive)
        #expect(installation.isInstalled(.tomedo))
        #expect(target.lastPathComponent == "tomedo.app")
        #expect(fm.fileExists(atPath: home.appending(path: "Applications/.localized").path(percentEncoded: false)))
        // Zweiter Versuch darf nichts überschreiben.
        #expect(throws: InstallError.self) { try installation.install(.tomedo, from: archive) }
    }

    @Test("Eigener Installationsort: ohne .localized, Vorgabe erkannt")
    func customFolder() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: work) }
        let source = work.appending(path: "src")
        try fm.createDirectory(at: source.appending(path: "tomedo.app/Contents"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appending(path: "tomedo.app/Contents/Info.plist"))
        let archive = work.appending(path: "tomedo.app.tar")
        try AppInstallation.run("/usr/bin/tar", ["-c", "-f", archive.path(percentEncoded: false),
                                                 "-C", source.path(percentEncoded: false), "tomedo.app"],
                                failure: { InstallError.archive($0) })
        let home = work.appending(path: "home")
        let folder = work.appending(path: "Praxis-Apps", directoryHint: .isDirectory)

        #expect(AppInstallation(home: home).isUserApplicationsFolder)
        #expect(AppInstallation(applicationsFolder: home.appending(path: "Applications/"), home: home).isUserApplicationsFolder)
        let custom = AppInstallation(applicationsFolder: folder, home: home)
        #expect(!custom.isUserApplicationsFolder)
        #expect(custom.isWritable)
        let target = try custom.install(.tomedo, from: archive)
        #expect(target.deletingLastPathComponent().lastPathComponent == "Praxis-Apps")
        #expect(!fm.fileExists(atPath: folder.appending(path: ".localized").path(percentEncoded: false)))
    }

    @Test("Ordner ohne Schreibrecht wird abgelehnt")
    func readOnlyFolder() {
        let installation = AppInstallation(applicationsFolder: URL(filePath: "/System/Applications/MacInstallerTest"))
        #expect(!installation.isWritable)
    }

    @Test func planSteps() {
        let plan = InstallPlan(server: ServerAddress(host: "s"), products: [.tomedo, .arzeko], addToDock: true)
        #expect(plan.steps.count == 7)
        #expect(plan.steps.last == .dock)
    }

    @Test func sha512() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        #expect(try Downloader.sha512(of: file).hasPrefix("ddaf35a193617aba"))
    }
}

@Suite("Serversuche")
struct DiscoveryTests {
    func ip(_ s: String) -> UInt32 {
        s.split(separator: ".").reduce(0) { $0 << 8 | UInt32($1)! }
    }

    @Test func hostsOfSlash24() {
        let net = LocalNetwork(address: ip("192.168.1.213"), prefixLength: 24)
        #expect(net.description == "192.168.1.0/24")
        #expect(net.hosts.count == 253)                        // .1 bis .254 ohne eigene
        #expect(net.hosts.first == ip("192.168.1.1"))
        #expect(net.hosts.last == ip("192.168.1.254"))
        #expect(!net.hosts.contains(ip("192.168.1.213")))
    }

    @Test func hostsOfSlash22() {
        #expect(LocalNetwork(address: ip("10.0.5.9"), prefixLength: 22).hosts.count == 1021)
    }

    @Test func privateRanges() {
        #expect(LocalNetwork(address: ip("10.1.2.3"), prefixLength: 24).isPrivate)
        #expect(LocalNetwork(address: ip("172.20.0.1"), prefixLength: 24).isPrivate)
        #expect(LocalNetwork(address: ip("192.168.7.5"), prefixLength: 24).isPrivate)
        #expect(!LocalNetwork(address: ip("172.32.0.1"), prefixLength: 24).isPrivate)
        #expect(!LocalNetwork(address: ip("100.64.0.1"), prefixLength: 8).isPrivate)  // VPN/CGNAT
    }

    @Test func currentNetworksAreSmall() {
        for net in LocalNetwork.current() {
            #expect(net.prefixLength >= 22)
            #expect(net.isPrivate)
        }
    }
}

/// Echttest gegen einen tomedo-Server – installiert nichts.
/// Start: `MACINSTALLER_TEST_SERVER=192.168.1.10 swift test`
@Suite("Echter tomedo-Server", .enabled(if: ProcessInfo.processInfo.environment["MACINSTALLER_TEST_SERVER"] != nil))
struct LiveServerTests {
    let server = TomedoServer(address: try! ServerAddress.parse(ProcessInfo.processInfo.environment["MACINSTALLER_TEST_SERVER"] ?? "x"))

    @Test func tomedoReachable() async {
        guard case .reachable(let size) = await server.check() else {
            Issue.record("Server liefert kein tomedo")
            return
        }
        #expect((size ?? 0) > 10_000_000)
    }

    /// Durchsucht das /24 des Testservers und muss ihn finden.
    @Test func discoveryFindsServer() async throws {
        let host = server.address.host
        let parts = host.split(separator: ".").compactMap { UInt32($0) }
        try #require(parts.count == 4, "MACINSTALLER_TEST_SERVER muss eine IPv4-Adresse sein")
        let ip = parts.reduce(0) { $0 << 8 | $1 }
        // Eigene Adresse im Netz simulieren (.0 ist nie ein Host), damit der Server selbst geprüft wird.
        let network = LocalNetwork(address: ip & 0xFFFF_FF00, prefixLength: 24)
        let start = Date()
        var found: [DiscoveredServer] = []
        for await server in ServerDiscovery().discover(in: [network]) { found.append(server) }
        #expect(found.contains { $0.address.host == host })
        #expect(Date().timeIntervalSince(start) < 30)
        print("Gefunden in \(Int(Date().timeIntervalSince(start))) s:", found.map { "\($0.address.host) \($0.hostName ?? "-")" })
    }

    @Test func arzekoRelease() async throws {
        let release = try await server.latestArzeko()
        #expect(release.url.host() == server.address.host)
        #expect(release.url.lastPathComponent.hasSuffix(".zip"))
    }

    /// Lädt wirklich herunter (einige hundert MB) und installiert in einen Wegwerf-Ordner.
    /// Nur Arzeko über den Installer, weil tomedo die echten Einstellungen beschreiben würde.
    /// Start zusätzlich mit `MACINSTALLER_TEST_INSTALL=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACINSTALLER_TEST_INSTALL"] == "1"))
    func fullInstallIntoTemporaryHome() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "macinstaller-e2e-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let plan = InstallPlan(server: server.address, products: [.arzeko], addToDock: false)
        let installed = try await Installer(plan: plan, home: home).run { _, _ in }
        let arzeko = try #require(installed[.arzeko])
        #expect(fm.fileExists(atPath: arzeko.appending(path: "Contents/Info.plist").path(percentEncoded: false)))
        #expect(fm.fileExists(atPath: ArzekoConnection.configFile(home: home).path(percentEncoded: false)))

        let archive = try await Downloader().download(server.tomedoArchiveURL) { _ in }
        defer { try? fm.removeItem(at: archive) }
        let tomedo = try AppInstallation(home: home).install(.tomedo, from: archive)
        #expect(fm.fileExists(atPath: tomedo.appending(path: "Contents/MacOS").path(percentEncoded: false)))
    }
}

/// Lädt eine größere Datei von einem lokalen Webserver und prüft, dass unterwegs Fortschritt ankommt.
/// Aufruf: `MACINSTALLER_TEST_DOWNLOAD_URL=http://127.0.0.1:<port>/datei swift test --filter Fortschritt`
@Suite("Fortschritt", .enabled(if: ProcessInfo.processInfo.environment["MACINSTALLER_TEST_DOWNLOAD_URL"] != nil))
struct ProgressTests {
    final class Collector: @unchecked Sendable {
        let lock = NSLock()
        var events: [DownloadProgress] = []
        func add(_ p: DownloadProgress) { lock.lock(); events.append(p); lock.unlock() }
    }

    @Test func downloadReportsProgressWithSize() async throws {
        let url = URL(string: ProcessInfo.processInfo.environment["MACINSTALLER_TEST_DOWNLOAD_URL"]!)!
        let collector = Collector()
        let file = try await Downloader().download(url) { collector.add($0) }
        defer { try? FileManager.default.removeItem(at: file) }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int64
        #expect(collector.events.count >= 2)
        #expect(collector.events.last?.expected == size)
        #expect(collector.events.last?.received == size)
        #expect(collector.events.contains { ($0.fraction ?? 0) > 0 && ($0.fraction ?? 1) < 1 })
    }
}
