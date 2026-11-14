import Foundation

/// Resolves the short invite links Spotify's apps share (`https://spotify.link/<id>`) into the
/// canonical `https://open.spotify.com/socialsession/<token>` link the plugin understands.
/// The short link carries no token: it redirects through Branch (`spotify.app.link`), whose landing
/// page holds the real link. Same approach as Windows ([FIX-349]), done on the host so the plugin
/// gets no network access of its own.
protocol JamShortLinkResolving: Sendable {
    /// The canonical link for a short link, or nil when it could not be resolved.
    func resolve(_ url: URL) async -> String?
}

enum JamShortLink {
    static let hosts: Set<String> = ["spotify.link", "spotify.app.link"]
    static let maxBytes = 512 * 1024
    static let maxRedirects = 5
    static let timeout: TimeInterval = 15

    /// The URL when `link` is an `https` short link on a Spotify short host, without credentials.
    static func shortURL(from link: String) -> URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), hosts.contains(host),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// A redirect target is followed only when it stays on Spotify's short hosts or `open.spotify.com`.
    static func isAllowedRedirect(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains(host) || host == "open.spotify.com"
    }

    /// The join token of the first `open.spotify.com/socialsession/<token>` in a page or URL
    /// (16-40 alphanumerics).
    static func token(in text: String) -> String? {
        let mark = "open.spotify.com/socialsession/"
        var rest = Substring(text)
        while let range = rest.range(of: mark) {
            let after = rest[range.upperBound...]
            let token = String(after.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber) }))
            if (16...40).contains(token.count) { return token }
            rest = after
        }
        return nil
    }

    static func canonical(token: String) -> String { "https://open.spotify.com/socialsession/\(token)" }

    /// Canonical link from the final URL (preferred) or the page body.
    static func canonicalLink(finalURL: URL?, body: String?) -> String? {
        if let finalURL, isAllowedRedirect(finalURL), let token = token(in: finalURL.absoluteString) { return canonical(token: token) }
        if let body, let token = token(in: body) { return canonical(token: token) }
        return nil
    }
}

/// Anonymous GET: ephemeral session (no cookies, no cache, no stored credentials), redirects limited
/// to Spotify hosts and `maxRedirects`, bounded time and size. Sends nothing from the Spotify session.
struct JamShortLinkResolver: JamShortLinkResolving {
    private final class Redirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private var count = 0
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            count += 1
            guard count <= JamShortLink.maxRedirects, let url = request.url, JamShortLink.isAllowedRedirect(url) else { return nil }
            return request
        }
    }

    func resolve(_ url: URL) async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = JamShortLink.timeout
        configuration.timeoutIntervalForResource = JamShortLink.timeout
        let session = URLSession(configuration: configuration, delegate: Redirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let link = JamShortLink.canonicalLink(finalURL: response.url, body: nil) { return link }
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return nil }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > JamShortLink.maxBytes { break }
            }
            return JamShortLink.canonicalLink(finalURL: nil, body: String(decoding: body, as: UTF8.self))
        } catch {
            return nil
        }
    }
}
