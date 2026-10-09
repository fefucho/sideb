import SwiftUI
import SideBCore

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies passed from the App
    let cookieStorage: CookieStorage
    let rustCore: SideBCore
    
    var onLoginCompleted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("login.heading"))
                    .font(.headline)

                Text(L10n.text("login.passkey_unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // WebView
            LoginWebView { cookieString in
                Task {
                    do {
                        // 1. Save to Keychain/File
                        try cookieStorage.saveSessionCookie(cookieString)
                        
                        // 2. Inject into Rust Core
                        rustCore.setCookie(cookie: cookieString)
                        
                        // 3. Notify app and dismiss
                        await MainActor.run {
                            onLoginCompleted()
                            dismiss()
                        }
                    } catch {
                        print("Error saving cookie: \(error)")
                    }
                }
            }
        }
        .frame(width: 500, height: 650)
    }
}
