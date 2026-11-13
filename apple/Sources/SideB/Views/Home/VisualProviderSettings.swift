import SwiftUI
import AppKit

/// The shell exposes only the generic provider contract; the executable owns Spotify details.
struct VisualProviderSettings: View {
    var onControlFocusChanged: (Bool) -> Void = { _ in }
    private enum Control: Hashable { case enable, token, save, remove, install, login }
    @FocusState private var focusedControl: Control?
    @State private var host = VisualProviderHost.shared
    @State private var spotifySession = SpotifySession.shared
    @State private var credential = ""
    @State private var pending = false
    @State private var failed = false
    @State private var showingManualToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("visualProvider.title")).font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(L10n.text("visualProvider.hint")).font(.system(size: 12)).foregroundStyle(.secondary)
            if let manifest = host.manifest {
                Text(verbatim: "\(manifest.name) · \(manifest.version)").font(.system(size: 12, weight: .medium))
                Toggle(L10n.text("visualProvider.enable"), isOn: $host.enabled)
                    .toggleStyle(.checkbox).disabled(!host.hasCredential || pending)
                    .accessibilityIdentifier("visual-provider-enable")
                    .focused($focusedControl, equals: .enable)

                if let auth = manifest.auth {
                    HStack(spacing: 8) {
                        if host.hasCredential {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(L10n.text("visualProvider.accountConnected"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Button(L10n.text("visualProvider.reconnect")) {
                                openLoginWindow(auth: auth, name: manifest.name)
                            }
                            .disabled(pending)
                            .focused($focusedControl, equals: .login)
                            if host.usesSpotifySession {
                                Button(L10n.text("visualProvider.spotifySignOut")) { signOutOfSpotify() }
                                    .disabled(pending)
                                    .accessibilityIdentifier("visual-provider-sign-out")
                            }
                        } else {
                            Button(L10n.text("visualProvider.signIn")) {
                                openLoginWindow(auth: auth, name: manifest.name)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pending)
                            .focused($focusedControl, equals: .login)
                        }
                    }

                    DisclosureGroup(isExpanded: $showingManualToken) {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField(L10n.text("visualProvider.token"), text: $credential)
                                .textFieldStyle(.roundedBorder).accessibilityIdentifier("visual-provider-token")
                                .focused($focusedControl, equals: .token)
                            Button(L10n.text("visualProvider.saveToken")) {
                                do { try host.saveCredential(credential); credential = ""; failed = false }
                                catch { failed = true }
                            }.disabled(credential.isEmpty || pending).focused($focusedControl, equals: .save)
                            Text(L10n.text("visualProvider.tokenHint")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    } label: {
                        Text(L10n.text("visualProvider.manualToken"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SecureField(L10n.text("visualProvider.token"), text: $credential)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("visual-provider-token")
                        .focused($focusedControl, equals: .token)
                    Button(L10n.text("visualProvider.saveToken")) {
                        do { try host.saveCredential(credential); credential = ""; failed = false }
                        catch { failed = true }
                    }.disabled(credential.isEmpty || pending).focused($focusedControl, equals: .save)
                    Text(L10n.text("visualProvider.tokenHint")).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                if host.usesSpotifySession {
                    Text(L10n.text("visualProvider.spotifyShared")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(L10n.text(host.statusKey)).font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("visual-provider-status")
                Button(L10n.text(host.usesSpotifySession ? "visualProvider.removeKeepsSession" : "visualProvider.remove")) {
                    pending = true
                    Task {
                        defer { pending = false }
                        do { try await host.uninstall(); credential = ""; failed = false }
                        catch { failed = true }
                    }
                }.disabled(pending).focused($focusedControl, equals: .remove)
            }
            // The Spotify session outlives the plugin (the Jam uses it), so it stays visible without one.
            if host.manifest == nil && spotifySession.hasCredential {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(L10n.text("visualProvider.spotifyOnlyAccount")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(L10n.text("visualProvider.spotifySignOut")) { signOutOfSpotify() }
                        .disabled(pending)
                        .accessibilityIdentifier("visual-provider-sign-out")
                }
            }
            Button(L10n.text("visualProvider.install")) { choosePackage() }.disabled(pending).focused($focusedControl, equals: .install)
            if failed { Text(L10n.text("visualProvider.error")).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .onChange(of: focusedControl) { _, value in onControlFocusChanged(value != nil) }
        .onDisappear { credential = ""; onControlFocusChanged(false) }
    }

    private func signOutOfSpotify() {
        pending = true
        Task {
            defer { pending = false }
            do { try await host.signOutOfSpotify(); failed = false } catch { failed = true }
        }
    }

    private func openLoginWindow(auth: VisualProviderAuth, name: String) {
        VisualProviderLoginWindowManager.shared.show(auth: auth, providerName: name) { token in
            do {
                try host.saveCredential(token)
                credential = ""
                failed = false
            } catch {
                failed = true
            }
        }
    }

    private func choosePackage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            pending = true
            Task { @MainActor in
                defer { pending = false }
                do { try await host.install(from: url); credential = ""; failed = false }
                catch { failed = true }
            }
        }
    }
}
