import Foundation

struct RedirectResolver {
    private static let userAgent = "LargeFileDownloader/1.0"

    func resolve(_ url: URL) async throws -> URL {
        do {
            return try await resolve(url, method: "HEAD")
        } catch {
            return try await resolve(url, method: "GET")
        }
    }

    private func resolve(_ url: URL, method: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let finalURL = response.url else {
            return url
        }
        return finalURL
    }
}
