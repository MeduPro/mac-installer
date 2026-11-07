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
/// Bewusst mit eigener `URLSession` und Delegate: Bei `URLSession.download(for:delegate:)`
/// ruft macOS `didWriteData` nicht auf, der Fortschritt käme nie an.
public struct Downloader: Sendable {
    public init() {}

    public func download(
        _ url: URL,
        expectedSize: Int64? = nil,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 60)
        // Ohne diese Angabe komprimiert der tomedo-Server das Archiv während der Übertragung
        // (Content-Encoding: gzip, ohne Content-Length); so kommt es mit Größe und schneller.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let delegate = DownloadDelegate(url: url, expectedSize: expectedSize, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
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

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<URL, Error>?
        var file: URL?
        var failure: Error?
        var lastReport = Date.distantPast
        var started = Date()
    }

    let url: URL
    let expectedSize: Int64?
    let progress: @Sendable (DownloadProgress) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(url: URL, expectedSize: Int64?, progress: @escaping @Sendable (DownloadProgress) -> Void) {
        self.url = url
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func start(_ continuation: CheckedContinuation<URL, Error>) {
        state.withLock {
            $0.continuation = continuation
            $0.started = Date()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        // höchstens vier Meldungen pro Sekunde, die letzte immer
        let rate: Double?? = state.withLock { s in
            let now = Date()
            guard now.timeIntervalSince(s.lastReport) >= 0.25 || totalBytesWritten == expected else { return nil }
            s.lastReport = now
            let elapsed = now.timeIntervalSince(s.started)
            return .some(elapsed >= 1 ? Double(totalBytesWritten) / elapsed : nil)
        }
        guard let rate else { return }
        progress(DownloadProgress(received: totalBytesWritten, expected: expected, bytesPerSecond: rate))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Die Datei verschwindet nach dieser Methode, also sofort sichern – aber nur bei HTTP 200.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            state.withLock { $0.failure = InstallError.download("Download von \(url.lastPathComponent) fehlgeschlagen (HTTP \(status)).") }
            return
        }
        let kept = FileManager.default.temporaryDirectory
            .appending(path: "MacInstaller-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            state.withLock { $0.file = kept }
        } catch {
            state.withLock { $0.failure = InstallError.download("Download von \(url.lastPathComponent) konnte nicht gesichert werden: \(error.localizedDescription)") }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, file, failure) = state.withLock { s in
            defer { s.continuation = nil }
            return (s.continuation, s.file, s.failure)
        }
        guard let continuation else { return }
        if let error {
            if let file { try? FileManager.default.removeItem(at: file) }
            if (error as? URLError)?.code == .cancelled {
                continuation.resume(throwing: InstallError.cancelled)
            } else {
                continuation.resume(throwing: InstallError.download("Download von \(url.lastPathComponent) fehlgeschlagen: \(error.localizedDescription)"))
            }
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if let file {
            continuation.resume(returning: file)
        } else {
            continuation.resume(throwing: InstallError.download("Download von \(url.lastPathComponent) lieferte keine Datei."))
        }
    }
}
