import Foundation

struct StreamResolver: Sendable {

    private static let audioExtensions: Set<String> = [
        "mp3", "aac", "ogg", "flac", "wav", "opus", "wma"
    ]

    func resolve(url: String) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw ResolverError.invalidURL
        }

        let pathExtension = requestURL.pathExtension.lowercased()

        // Known playlist formats — resolve to stream URL
        if pathExtension == "pls" {
            return try await resolvePLS(url: requestURL)
        } else if pathExtension == "m3u" || pathExtension == "m3u8" {
            return try await resolveM3U(url: requestURL)
        }

        // Known audio extensions — already a direct stream
        if Self.audioExtensions.contains(pathExtension) {
            return url
        }

        // Unknown extension — check for redirects (e.g. CDN load balancers)
        let resolved = try await resolveRedirects(url: requestURL)

        // If the resolved URL is a playlist, resolve it
        let resolvedExt = resolved.pathExtension.lowercased()
        if resolvedExt == "pls" {
            return try await resolvePLS(url: resolved)
        } else if resolvedExt == "m3u" || resolvedExt == "m3u8" {
            return try await resolveM3U(url: resolved)
        }

        let result = resolved.absoluteString
        if result != url {
            print("[StreamResolver] Resolved redirect: \(url) -> \(result)")
        }
        return result
    }

    /// Follow one redirect using GET with a delegate that cancels after headers.
    /// This avoids downloading infinite audio stream bodies.
    private func resolveRedirects(url: URL) async throws -> URL {
        let delegate = HeaderOnlyDelegate()
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let _ = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // Expected — delegate cancelled after receiving headers
        }

        if let redirectURL = delegate.capturedRedirectURL {
            let absolute = redirectURL.absoluteURL
            print("[StreamResolver] Resolved redirect: \(url) -> \(absolute)")
            return absolute
        }
        return url
    }

    private func resolvePLS(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        let content = String(data: data, encoding: .utf8) ?? ""

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("file1=") || trimmed.lowercased().hasPrefix("file=") {
                let value = String(trimmed.drop(while: { $0 != "=" }).dropFirst())
                if !value.isEmpty { return value }
            }
        }

        throw ResolverError.noStreamFound
    }

    private func resolveM3U(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        let content = String(data: data, encoding: .utf8) ?? ""

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return trimmed
            }
        }

        throw ResolverError.noStreamFound
    }

    enum ResolverError: LocalizedError {
        case invalidURL
        case noStreamFound

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid stream URL"
            case .noStreamFound: return "Could not resolve stream URL from playlist"
            }
        }
    }
}

/// Captures redirect URLs and cancels the request after headers arrive,
/// preventing infinite downloads from audio streams.
private final class HeaderOnlyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedRedirectURL: URL?

    var capturedRedirectURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _capturedRedirectURL
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        _capturedRedirectURL = request.url
        lock.unlock()
        completionHandler(nil) // Don't follow — we captured the URL
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Got headers — cancel to avoid downloading stream body
        completionHandler(.cancel)
    }
}
