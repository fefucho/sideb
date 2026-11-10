import SwiftUI
import WebKit
import AppKit

@MainActor
final class VisualProviderLoginWindowManager: NSObject, NSWindowDelegate {
    static let shared = VisualProviderLoginWindowManager()
    private var window: NSWindow?

    func show(auth: VisualProviderAuth, providerName: String, onTokenAcquired: @escaping (String) -> Void) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 540, height: 680)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let win = NSWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        win.title = String(format: L10n.text("visualProvider.loginSheetTitle"), providerName)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let contentView = VisualProviderLoginWindowContent(
            auth: auth,
            providerName: providerName,
            onTokenAcquired: { [weak self, weak win] token in
                onTokenAcquired(token)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1100))
                    win?.close()
                    self?.window = nil
                }
            },
            onClose: { [weak self, weak win] in
                win?.close()
                self?.window = nil
            }
        )

        win.contentView = NSHostingView(rootView: contentView)
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct VisualProviderLoginWindowContent: View {
    let auth: VisualProviderAuth
    let providerName: String
    var onTokenAcquired: (String) -> Void
    var onClose: () -> Void

    @State private var isExtracting = false
    @State private var tokenSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: L10n.text("visualProvider.loginSheetTitle"), providerName))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("visualProvider.loginSheetHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if tokenSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(L10n.text("visualProvider.accountConnected"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.trailing, 8)
                } else if isExtracting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.text("visualProvider.authenticating"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 8)
                }
                Button(L10n.text("visualProvider.close")) {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            VisualProviderLoginWebView(
                auth: auth,
                onExtracting: { isExtracting = true },
                onTokenSuccess: { token in
                    isExtracting = false
                    tokenSuccess = true
                    onTokenAcquired(token)
                }
            )
        }
        .frame(minWidth: 480, minHeight: 600)
    }
}

struct VisualProviderLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let auth: VisualProviderAuth
    let providerName: String
    var onTokenAcquired: (String) -> Void

    @State private var isExtracting = false
    @State private var tokenSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: L10n.text("visualProvider.loginSheetTitle"), providerName))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("visualProvider.loginSheetHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if tokenSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(L10n.text("visualProvider.accountConnected"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.trailing, 8)
                } else if isExtracting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.text("visualProvider.authenticating"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 8)
                }
                Button(L10n.text("visualProvider.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Web view
            VisualProviderLoginWebView(
                auth: auth,
                onExtracting: { isExtracting = true },
                onTokenSuccess: { token in
                    isExtracting = false
                    tokenSuccess = true
                    onTokenAcquired(token)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1100))
                        dismiss()
                    }
                }
            )
        }
        .frame(width: 520, height: 660)
    }
}

struct VisualProviderLoginWebView: NSViewRepresentable {
    let auth: VisualProviderAuth
    var onExtracting: () -> Void
    var onTokenSuccess: (String) -> Void

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "providerTokenHandler")

        let scriptSource = VisualProviderTokenExtractor.scriptSource(handlerName: "providerTokenHandler")
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(userScript)
        configuration.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.safariUserAgent
        webView.navigationDelegate = context.coordinator

        #if DEBUG
        webView.isInspectable = true
        #endif

        if let url = URL(string: auth.loginUrl) {
            var request = URLRequest(url: url)
            request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
            webView.load(request)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: VisualProviderLoginWebView
        private var hasExtractedToken = false
        private var pollingTask: Task<Void, Never>?

        init(parent: VisualProviderLoginWebView) {
            self.parent = parent
        }

        deinit {
            pollingTask?.cancel()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "providerTokenHandler",
                  let token = message.body as? String,
                  !token.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.handleToken(token)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            checkAndExtract(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkAndExtract(from: webView)
        }

        private func checkAndExtract(from webView: WKWebView) {
            guard !hasExtractedToken, let host = webView.url?.host else { return }
            if host.contains(parent.auth.targetHost) {
                parent.onExtracting()
                Task { @MainActor [weak self, weak webView] in
                    guard let self, let webView else { return }
                    await self.attemptExtraction(from: webView)
                }
                startPolling(in: webView)
            }
        }

        private func startPolling(in webView: WKWebView) {
            guard pollingTask == nil else { return }
            pollingTask = Task { [weak self, weak webView] in
                for _ in 0..<40 {
                    try? await Task.sleep(for: .seconds(1.2))
                    guard !Task.isCancelled, let self, !self.hasExtractedToken, let wv = webView else { return }
                    await self.attemptExtraction(from: wv)
                }
            }
        }

        private func handleToken(_ token: String) {
            guard !hasExtractedToken else { return }
            hasExtractedToken = true
            pollingTask?.cancel()
            pollingTask = nil
            parent.onTokenSuccess(token)
        }

        private func attemptExtraction(from webView: WKWebView) async {
            guard !hasExtractedToken else { return }
            let tokenUrl = parent.auth.tokenUrl
            let script = VisualProviderTokenExtractor.pageExtractionScript(tokenUrl: tokenUrl, handlerName: "providerTokenHandler")
            do {
                let result = try await webView.callAsyncJavaScript(
                    script,
                    arguments: ["tokenUrl": tokenUrl],
                    in: nil,
                    contentWorld: .page
                )
                guard !hasExtractedToken else { return }
                if let token = result as? String, !token.isEmpty {
                    handleToken(token)
                }
            } catch {}
        }
    }
}
