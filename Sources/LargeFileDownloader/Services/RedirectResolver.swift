import Foundation

struct RedirectResolver {
    private static let userAgent = "LargeFileDownloader/1.0"

    func resolve(_ url: URL) async throws -> URL {
        do {
            let resolved = try await resolve(url, method: "HEAD")
            return unwrapWrapperURLIfNeeded(resolved)
        } catch {
            let resolved = try await resolve(url, method: "GET")
            return unwrapWrapperURLIfNeeded(resolved)
        }
    }

    private func resolve(_ url: URL, method: String) async throws -> ResolvedResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let finalURL = response.url else {
            return ResolvedResponse(url: url, mimeType: response.mimeType)
        }
        return ResolvedResponse(url: finalURL, mimeType: response.mimeType)
    }

    private func unwrapWrapperURLIfNeeded(_ response: ResolvedResponse) -> URL {
        guard let mimeType = response.mimeType?.lowercased(),
              mimeType.contains("html") else {
            return response.url
        }

        return Self.unwrapDownloadURL(from: response.url) ?? response.url
    }

    static func unwrapDownloadURL(from url: URL, maxDepth: Int = 5) -> URL? {
        var currentURL = url
        var didUnwrap = false
        var visited = Set<String>()

        for _ in 0..<maxDepth {
            guard let nestedURL = embeddedDownloadURL(in: currentURL) else {
                break
            }

            let key = nestedURL.absoluteString
            guard visited.insert(key).inserted else {
                break
            }

            currentURL = nestedURL
            didUnwrap = true
        }

        return didUnwrap ? currentURL : nil
    }

    private static func embeddedDownloadURL(in url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        guard let encodedURL = queryItems.first(where: { $0.name.caseInsensitiveCompare("url") == .orderedSame })?.value else {
            return nil
        }

        let trimmed = encodedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let nestedURL = URL(string: trimmed),
              let scheme = nestedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return nestedURL
    }

    private struct ResolvedResponse {
        let url: URL
        let mimeType: String?
    }
}
