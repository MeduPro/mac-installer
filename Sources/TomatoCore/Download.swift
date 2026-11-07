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

    public var fraction: Double? {
        guard let expected, expected > 0 else { return nil }
        return min(1, Double(received) / Double(expected))
    }
}

/// Lädt eine Datei in eine temporäre Datei und meldet den Fortschritt.
public struct Downloader: Sendable {
    public init() {}

    public func download(
        _ url: URL,
        expectedSize: Int64? = nil,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 60)
        // tomedo-Server liefern das Archiv sonst gzip-komprimiert und deutlich langsamer
        // aus (siehe tomi bzw. forum.tomedo.de, „Downloads um 500 % beschleunigen“).
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let delegate = ProgressDelegate(expectedSize: expectedSize, progress: progress)
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        } catch is CancellationError {
            throw InstallError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw InstallError.cancelled
        } catch {
            throw InstallError.download("Download von \(url.lastPathComponent) fehlgeschlagen: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw InstallError.download("Download von \(url.lastPathComponent) fehlgeschlagen (HTTP \(code)).")
        }
        // Die von URLSession gelieferte Datei wird beim Rücksprung gelöscht – also sichern.
        let kept = FileManager.default.temporaryDirectory
            .appending(path: "TomatoInstaller-\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: tempURL, to: kept)
        return kept
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

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let expectedSize: Int64?
    let progress: @Sendable (DownloadProgress) -> Void
    /// Zeitpunkt der letzten Meldung – höchstens zehn Meldungen pro Sekunde.
    private let lastReport = OSAllocatedUnfairLock(initialState: Date.distantPast)

    init(expectedSize: Int64?, progress: @escaping @Sendable (DownloadProgress) -> Void) {
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let due = lastReport.withLock { last in
            let now = Date()
            guard now.timeIntervalSince(last) >= 0.1 || totalBytesWritten == expected else { return false }
            last = now
            return true
        }
        if due { progress(DownloadProgress(received: totalBytesWritten, expected: expected)) }
    }

    // Wird bei download(for:delegate:) nicht aufgerufen, ist aber Pflicht im Protokoll.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
