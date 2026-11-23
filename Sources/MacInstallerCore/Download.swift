import CryptoKit
import os
import Foundation

public enum InstallError: Error, LocalizedError, Equatable {
    case server(String)
    case download(String)
    case checksumMismatch(String)
    case archive(String)
    case configuration(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .server(let m), .download(let m), .archive(let m), .configuration(let m): m
        case .checksumMismatch(let name): "Die Prüfsumme von \(name) stimmt nicht – der Download ist beschädigt. Bitte erneut versuchen."
        case .cancelled: "Abgebrochen."
        }
    }
}

/// Fortschritt eines Downloads.
public struct DownloadProgress: Sendable, Equatable {
    public var received: Int64
    public var expected: Int64?
    /// Mittlere Geschwindigkeit seit Beginn, sobald sie sich sinnvoll schätzen lässt.
    public var bytesPerSecond: Double?

    public init(received: Int64, expected: Int64?, bytesPerSecond: Double? = nil) {
        self.received = received
        self.expected = expected
        self.bytesPerSecond = bytesPerSecond
    }

    public var fraction: Double? {
        guard let expected, expected > 0 else { return nil }
        return min(1, Double(received) / Double(expected))
    }

    /// Geschätzte Restzeit in Sekunden.
    public var remaining: TimeInterval? {
        guard let expected, let bytesPerSecond, bytesPerSecond > 0, expected >= received else { return nil }
        return Double(expected - received) / bytesPerSecond
    }
}

/// Lädt eine Datei in eine temporäre Datei und meldet den Fortschritt.
///
/// Bricht die Verbindung ab (WLAN-Lücke, VPN, Stillstand über `idleTimeout`), lädt der
/// Downloader nach einer kurzen Pause ab der erreichten Stelle weiter (`Range`). Der
/// tomedo-Server beantwortet das mit 206; antwortet ein Server mit 200, beginnt der
/// Download von vorn. Jeder Versuch steht im Protokoll (`InstallLog`).
public struct Downloader: Sendable {
    public var maxAttempts: Int
    public var retryDelay: Duration
    public var idleTimeout: TimeInterval

    public init(maxAttempts: Int = 6, retryDelay: Duration = .seconds(3), idleTimeout: TimeInterval = 60) {
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
        self.idleTimeout = idleTimeout
    }

    public func download(
        _ url: URL,
        expectedSize: Int64? = nil,
        kopfzeilen: [String: String] = [:],
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let name = url.lastPathComponent
        let target = FileManager.default.temporaryDirectory
            .appending(path: "\(InstallLog.dateiPraefix)-\(UUID().uuidString)-\(name)")
        guard FileManager.default.createFile(atPath: target.path(percentEncoded: false), contents: nil) else {
            throw InstallError.download("Für den Download von \(name) ließ sich keine Datei anlegen.")
        }
        let stand = Stand(expected: expectedSize, progress: progress)
        InstallLog.schreiben("Download \(url.absoluteString) beginnt")

        var versuch = 0
        while true {
            versuch += 1
            let ergebnis = await einVersuch(url, kopfzeilen: kopfzeilen, in: target, stand: stand)
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: target)
                InstallLog.schreiben("Download \(name) vom Benutzer abgebrochen")
                throw InstallError.cancelled
            }
            let (geladen, gesamt) = stand.groessen
            switch ergebnis {
            case .fertig:
                InstallLog.schreiben("Download \(name) fertig: \(Self.groesse(geladen)), \(versuch) Versuch(e)")
                return target
            case .endgueltig(let fehler):
                try? FileManager.default.removeItem(at: target)
                InstallLog.schreiben("Download \(name) fehlgeschlagen (Versuch \(versuch)): \(fehler)")
                throw InstallError.download("Download von \(name) fehlgeschlagen: \(fehler)")
            case .wiederholbar(let fehler):
                let stelle = "\(Self.groesse(geladen))" + (gesamt.map { " von \(Self.groesse($0))" } ?? "")
                InstallLog.schreiben("Download \(name) unterbrochen bei \(stelle) (Versuch \(versuch)/\(maxAttempts)): \(fehler)")
                guard versuch < maxAttempts else {
                    try? FileManager.default.removeItem(at: target)
                    throw InstallError.download(
                        "Download von \(name) nach \(versuch) Versuchen abgebrochen, zuletzt bei \(stelle): \(fehler) "
                        + "Bitte Netzwerkverbindung prüfen und erneut versuchen. Einzelheiten stehen im Protokoll "
                        + "(\(InstallLog.anzeigePfad)).")
                }
                do {
                    // Pausen verdoppeln sich (3, 6, 12, 24, 48 s): Nach dem Aufwachen braucht das WLAN etwas.
                    try await Task.sleep(for: retryDelay * (1 << (versuch - 1)))
                } catch {
                    try? FileManager.default.removeItem(at: target)
                    throw InstallError.cancelled
                }
            }
        }
    }

    private func einVersuch(_ url: URL, kopfzeilen: [String: String], in datei: URL,
                           stand: Stand) async -> Versuchsergebnis {
        var request = URLRequest(url: url, timeoutInterval: idleTimeout)
        for (name, wert) in kopfzeilen { request.setValue(wert, forHTTPHeaderField: name) }
        // Ohne diese Angabe komprimiert der tomedo-Server das Archiv während der Übertragung
        // (Content-Encoding: gzip, ohne Content-Length); so kommt es mit Größe und schneller.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let ab = stand.groessen.geladen
        if ab > 0 { request.setValue("bytes=\(ab)-", forHTTPHeaderField: "Range") }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: datei)
            try handle.truncate(atOffset: UInt64(ab))
        } catch {
            return .endgueltig("Die Datei ließ sich nicht schreiben: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        let delegate = VersuchDelegate(handle: handle, stand: stand, ab: ab)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    static func groesse(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// SHA-512 einer Datei als Hex-Text, blockweise gelesen.
    public static func sha512(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA512()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum Versuchsergebnis: Sendable {
    case fertig
    case wiederholbar(String)
    case endgueltig(String)
}

/// Was über alle Versuche erhalten bleibt: geladene Bytes, Gesamtgröße, Fortschrittsmeldung.
final class Stand: @unchecked Sendable {
    private struct Werte {
        var geladen: Int64 = 0
        var expected: Int64?
        var started = Date()
        var lastReport = Date.distantPast
    }
    private let werte: OSAllocatedUnfairLock<Werte>
    private let progress: @Sendable (DownloadProgress) -> Void

    init(expected: Int64?, progress: @escaping @Sendable (DownloadProgress) -> Void) {
        werte = OSAllocatedUnfairLock(initialState: Werte(expected: expected))
        self.progress = progress
    }

    var groessen: (geladen: Int64, gesamt: Int64?) {
        werte.withLock { ($0.geladen, $0.expected) }
    }

    func setzen(geladen: Int64, gesamt: Int64?) {
        werte.withLock { w in
            w.geladen = geladen
            if let gesamt { w.expected = gesamt }
        }
    }

    func dazu(_ bytes: Int64) {
        // höchstens vier Meldungen pro Sekunde, die letzte immer
        let meldung: DownloadProgress? = werte.withLock { w in
            w.geladen += bytes
            let now = Date()
            guard now.timeIntervalSince(w.lastReport) >= 0.25 || w.geladen == w.expected else { return nil }
            w.lastReport = now
            let elapsed = now.timeIntervalSince(w.started)
            return DownloadProgress(received: w.geladen, expected: w.expected,
                                    bytesPerSecond: elapsed >= 1 ? Double(w.geladen) / elapsed : nil)
        }
        if let meldung { progress(meldung) }
    }
}

/// Ein Versuch: schreibt die Antwort direkt in die Datei, ab der Stelle `ab`.
final class VersuchDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Zustand {
        var continuation: CheckedContinuation<Versuchsergebnis, Never>?
        var ergebnis: Versuchsergebnis?
    }

    let handle: FileHandle
    let stand: Stand
    let ab: Int64
    private let zustand = OSAllocatedUnfairLock(initialState: Zustand())

    init(handle: FileHandle, stand: Stand, ab: Int64) {
        self.handle = handle
        self.stand = stand
        self.ab = ab
    }

    func start(_ continuation: CheckedContinuation<Versuchsergebnis, Never>) {
        zustand.withLock { $0.continuation = continuation }
    }

    private func vormerken(_ ergebnis: Versuchsergebnis) {
        zustand.withLock { if $0.ergebnis == nil { $0.ergebnis = ergebnis } }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            vormerken(.endgueltig("Keine HTTP-Antwort."))
            return completionHandler(.cancel)
        }
        switch http.statusCode {
        case 206:
            guard let bereich = Self.contentRange(http), bereich.start == ab else {
                // Unerwarteter Bereich: lieber von vorn als eine zusammengestückelte Datei.
                stand.setzen(geladen: 0, gesamt: nil)
                vormerken(.wiederholbar("Der Server lieferte einen anderen Abschnitt als angefragt; der Download beginnt von vorn."))
                return completionHandler(.cancel)
            }
            stand.setzen(geladen: ab, gesamt: bereich.gesamt)
        case 200:
            if ab > 0 {
                // Server kann nicht weiterladen: von vorn.
                do { try handle.truncate(atOffset: 0) } catch {
                    vormerken(.endgueltig("Die Datei ließ sich nicht schreiben: \(error.localizedDescription)"))
                    return completionHandler(.cancel)
                }
            }
            stand.setzen(geladen: 0, gesamt: http.expectedContentLength > 0 ? http.expectedContentLength : nil)
        case 500...599:
            vormerken(.wiederholbar("Der Server antwortete mit HTTP \(http.statusCode)."))
            return completionHandler(.cancel)
        default:
            vormerken(.endgueltig("Der Server antwortete mit HTTP \(http.statusCode)."))
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle.write(contentsOf: data)
            stand.dazu(Int64(data.count))
        } catch {
            vormerken(.endgueltig("Die Datei ließ sich nicht schreiben: \(error.localizedDescription)"))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, vorgemerkt) = zustand.withLock { z in
            defer { z.continuation = nil }
            return (z.continuation, z.ergebnis)
        }
        guard let continuation else { return }
        if let vorgemerkt { return continuation.resume(returning: vorgemerkt) }
        if let error {
            let code = (error as? URLError)?.code
            let text = "\(error.localizedDescription) (\(code.map { "URLError \($0.rawValue)" } ?? "Fehler"))"
            return continuation.resume(returning: Self.wiederholbar(code) ? .wiederholbar(text) : .endgueltig(text))
        }
        let (geladen, gesamt) = stand.groessen
        if let gesamt, geladen < gesamt {
            return continuation.resume(returning: .wiederholbar("Die Verbindung endete vorzeitig."))
        }
        continuation.resume(returning: .fertig)
    }

    /// Netzwerkfehler, nach denen ein neuer Versuch Sinn hat.
    static func wiederholbar(_ code: URLError.Code?) -> Bool {
        guard let code else { return false }
        let codes: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .resourceUnavailable, .internationalRoamingOff,
            .callIsActive, .dataNotAllowed, .secureConnectionFailed, .cannotLoadFromNetwork,
            .cancelled,  // vom System (z. B. Ruhezustand); ein Abbruch durch den Benutzer wird vorher erkannt
        ]
        return codes.contains(code)
    }

    /// `Content-Range: bytes 100-199/1000` → Anfang 100, gesamt 1000.
    static func contentRange(_ http: HTTPURLResponse) -> (start: Int64, gesamt: Int64?)? {
        guard let wert = http.value(forHTTPHeaderField: "Content-Range"),
              let range = wert.range(of: #"bytes\s+(\d+)-(\d+)/(\d+|\*)"#, options: .regularExpression)
        else { return nil }
        let teile = wert[range].dropFirst(5).trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == "-" || $0 == "/" })
        guard teile.count == 3, let start = Int64(teile[0]) else { return nil }
        return (start, Int64(teile[2]))
    }
}
