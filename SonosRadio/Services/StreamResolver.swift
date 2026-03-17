import Foundation

struct StreamResolver: Sendable {

    func resolve(url: String) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw ResolverError.invalidURL
        }

        let pathExtension = requestURL.pathExtension.lowercased()
        if pathExtension == "pls" {
            return try await resolvePLS(url: requestURL)
        } else if pathExtension == "m3u" || pathExtension == "m3u8" {
            return try await resolveM3U(url: requestURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        let (_, response) = try await URLSession.shared.data(for: request)
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("audio/x-scpls") || contentType.contains("application/pls") {
            return try await resolvePLS(url: requestURL)
        } else if contentType.contains("audio/x-mpegurl") || contentType.contains("application/vnd.apple.mpegurl") {
            return try await resolveM3U(url: requestURL)
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
