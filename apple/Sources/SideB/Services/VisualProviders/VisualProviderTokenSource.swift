import Foundation
import WebKit

/// Obtains a fresh credential for a provider without user interaction, reusing the session the
/// user created once in the login window (shared WebKit data store). Never prompts.
@MainActor protocol VisualProviderTokenSource {
    /// `rejected` is a token the provider already refused. It must never be returned again.
    func acquire(auth: VisualProviderAuth, rejecting rejected: String?) async -> String?
}

/// Tries independent strategies in order. Each runs in its own throw-away web view so a page that
/// is stuck, cached or served a different layout cannot poison the next attempt.
@MainActor struct WebViewVisualProviderTokenSource: VisualProviderTokenSource {
    func acquire(auth: VisualProviderAuth, rejecting rejected: String?) async -> String? {
        for strategy in VisualProviderSilentTokenRefresher.Strategy.allCases {
            if Task.isCancelled { return nil }
            let refresher = VisualProviderSilentTokenRefresher(auth: auth, strategy: strategy, rejected: rejected)
            if let token = await refresher.refresh() { return token }
        }
        return nil
    }
}

@MainActor
final class VisualProviderSilentTokenRefresher: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    enum Strategy: CaseIterable {
        /// Load the site root: its own scripts request a token, which the injected hook observes.
        case homePage
        /// Load another page so a different set of authenticated requests is issued, bypassing caches.
        case searchPage
        /// Navigate straight to the token endpoint and read its JSON body.
        case tokenEndpoint
    }

    private static let handlerName = "silentTokenHandler"
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let auth: VisualProviderAuth
    private let strategy: Strategy
    private let rejected: String?
    private var extractionsInFlight = 0

    init(auth: VisualProviderAuth, strategy: Strategy = .homePage, rejected: String? = nil) {
        self.auth = auth
        self.strategy = strategy
        self.rejected = rejected
    }

    func refresh() async -> String? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let ucc = WKUserContentController()
            ucc.add(self, name: Self.handlerName)
            if strategy != .tokenEndpoint {
                ucc.addUserScript(WKUserScript(source: VisualProviderTokenExtractor.scriptSource(handlerName: Self.handlerName),
                                               injectionTime: .atDocumentStart, forMainFrameOnly: false))
            }
            config.userContentController = ucc

            let wv = WKWebView(frame: .zero, configuration: config)
            wv.customUserAgent = VisualProviderLoginWebView.safariUserAgent
            wv.navigationDelegate = self
            self.webView = wv

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(14))
                guard !Task.isCancelled else { return }
                self?.finish(with: nil)
            }

            let target: URL?
            switch strategy {
            case .homePage: target = URL(string: "https://\(auth.targetHost)/")
            case .searchPage: target = URL(string: "https://\(auth.targetHost)/search")
            case .tokenEndpoint: target = URL(string: auth.tokenUrl)
            }
            guard let url = target else { finish(with: nil); return }
            wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == Self.handlerName, let token = message.body as? String {
            accept(token)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.hasSuffix(auth.targetHost) == true else { return }
        extractToken(from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    /// A token the provider already rejected, or an empty one, is not progress: keep waiting.
    private func accept(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != rejected, continuation != nil else { return }
        finish(with: cleaned)
    }

    private func extractToken(from webView: WKWebView) {
        guard extractionsInFlight == 0 else { return }
        extractionsInFlight += 1
        Task { @MainActor [weak self, weak webView] in
            defer { self?.extractionsInFlight -= 1 }
            // The page issues its own token request a moment after load; poll briefly.
            for attempt in 0..<6 {
                guard let self, let webView, self.continuation != nil else { return }
                let script = self.strategy == .tokenEndpoint
                    ? VisualProviderTokenExtractor.documentBodyScript
                    : VisualProviderTokenExtractor.pageExtractionScript(tokenUrl: self.auth.tokenUrl, handlerName: Self.handlerName)
                let arguments: [String: Any] = self.strategy == .tokenEndpoint ? [:] : ["tokenUrl": self.auth.tokenUrl]
                if let result = try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page),
                   let token = result as? String {
                    self.accept(token)
                }
                if attempt < 5 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }

    private func finish(with token: String?) {
        guard continuation != nil else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        continuation?.resume(returning: token)
        continuation = nil
    }
}
