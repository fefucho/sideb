import Foundation
import AppKit

/// Representa la información de un release publicado en GitHub.
public struct ReleaseInfo: Equatable, Sendable {
    public let tagName: String
    public let version: String
    public let releaseNotes: String
    public let downloadURL: URL
    public let publishedAt: String?
    var displayReleaseNotes: String {
        releaseNotes.isEmpty ? L10n.text("update.no_release_notes") : releaseNotes
    }

    public init(tagName: String, version: String, releaseNotes: String, downloadURL: URL, publishedAt: String?) {
        self.tagName = tagName
        self.version = version
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
    }
}

/// Estado del ciclo de vida del actualizador.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(progress: Double)
    case installing
    case failed(String)
}

/// Servicio que gestiona la comprobación, descarga y aplicación de actualizaciones desde GitHub Releases.
@MainActor
@Observable
public final class UpdateService: NSObject, @unchecked Sendable {
    public static let shared = UpdateService()

    public var repoOwner: String = "fefucho"
    public var repoName: String = "SIDE-B-CLIENT-NATIVE"

    public var state: UpdateState = .idle
    public var isSheetPresented: Bool = false
    private(set) var failureMessage: AppMessage?

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    public override init() {
        super.init()
        // Cargar repositorios personalizados si están en Info.plist
        if let customOwner = Bundle.main.infoDictionary?["GitHubRepoOwner"] as? String, !customOwner.isEmpty {
            self.repoOwner = customOwner
        }
        if let customRepo = Bundle.main.infoDictionary?["GitHubRepoName"] as? String, !customRepo.isEmpty {
            self.repoName = customRepo
        }
    }

    private let skippedVersionKey = "SideB_SkippedVersion"
    private let lastCheckDateKey = "SideB_LastUpdateCheckDate"

    public var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedVersionKey) }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: skippedVersionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: skippedVersionKey)
            }
        }
    }

    public var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckDateKey) }
    }

    /// Oculta el diálogo y guarda la versión para no volver a alertar automáticamente.
    public func skipVersion(_ version: String) {
        skippedVersion = version
        isSheetPresented = false
        state = .idle
        failureMessage = nil
    }

    /// Reinicia la versión omitida para permitir futuras alertas.
    public func resetSkippedVersion() {
        skippedVersion = nil
    }

    /// Determina si se debe notificar al usuario de una versión remota.
    public func shouldNotifyUser(for remoteVersion: String, manual: Bool) -> Bool {
        if manual {
            return true
        }
        if let skipped = skippedVersion, skipped == remoteVersion {
            return false
        }
        return true
    }

    /// Comprueba si existe una versión más reciente en GitHub Releases.
    public func checkForUpdates(manual: Bool = false) async {
        failureMessage = nil
        state = .checking
        if manual {
            isSheetPresented = true
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            setFailure(AppMessage(key: "update.error_invalid_github_url"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SideB/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                if manual { setFailure(AppMessage(key: "update.error_invalid_server_response")) }
                else { state = .idle }
                return
            }

            if httpResponse.statusCode == 404 {
                if manual { setFailure(AppMessage(key: "update.error_no_release", args: ["\(repoOwner)/\(repoName)"])) }
                else { state = .idle }
                return
            }

            guard httpResponse.statusCode == 200 else {
                if manual { setFailure(AppMessage(key: "update.error_github_status", args: [String(httpResponse.statusCode)])) }
                else { state = .idle }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if manual { setFailure(AppMessage(key: "update.error_release_format")) }
                else { state = .idle }
                return
            }

            let remoteVersion = Self.cleanVersion(tagName)
            let body = json["body"] as? String ?? ""
            let publishedAt = json["published_at"] as? String

            let downloadURL = Self.macOSDownloadURL(in: json["assets"] as? [[String: Any]] ?? [])

            guard let finalDownloadURL = downloadURL else {
                if manual { setFailure(AppMessage(key: "update.error_release_missing_zip", args: [tagName])) }
                else { state = .idle }
                return
            }

            lastCheckDate = Date()

            if Self.isVersion(remoteVersion, newerThan: currentVersion) {
                let release = ReleaseInfo(
                    tagName: tagName,
                    version: remoteVersion,
                    releaseNotes: body,
                    downloadURL: finalDownloadURL,
                    publishedAt: publishedAt
                )

                if shouldNotifyUser(for: remoteVersion, manual: manual) {
                    state = .available(release)
                    isSheetPresented = true
                } else {
                    state = .idle
                }
            } else {
                state = manual ? .upToDate : .idle
            }
        } catch {
            if manual { setFailure(AppMessage(key: "update.error_connection", args: [error.localizedDescription])) }
            else { state = .idle }
        }
    }

    /// Descarga la actualización e inicia el reemplazo en caliente.
    public func downloadAndInstall(release: ReleaseInfo) async {
        failureMessage = nil
        state = .downloading(progress: 0.0)

        do {
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let tempDownloadedURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.downloadContinuation = continuation
                let task = session.downloadTask(with: release.downloadURL)
                self.downloadTask = task
                task.resume()
            }

            state = .installing

            let updatesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.fefucho.SideB.v2/Updates", isDirectory: true)
            try? FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)

            let zipFile = updatesDir.appendingPathComponent("SideB-\(release.version).zip")
            try? FileManager.default.removeItem(at: zipFile)
            try FileManager.default.moveItem(at: tempDownloadedURL, to: zipFile)

            try executeTrampolineUpdate(zipURL: zipFile)
        } catch {
            setFailure(AppMessage(key: "update.error_install", args: [error.localizedDescription]))
        }
    }

    private func setFailure(_ message: AppMessage) {
        failureMessage = message
        state = .failed(message.text)
    }

    /// Lanza un proceso desacoplado que espera a que la app actual cierre,
    /// reemplaza el `.app` bundle, elimina la cuarentena y reabre la nueva versión.
    private func executeTrampolineUpdate(zipURL: URL) throws {
        let currentAppPath = Bundle.main.bundleURL.path
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let updatesDir = zipURL.deletingLastPathComponent().path
        let extractDir = "\(updatesDir)/extracted"

        let trampolineScript = """
        #!/bin/bash
        set -e
        # 1. Esperar a que la instancia actual de Side B termine
        WAIT_COUNT=0
        while kill -0 "\(currentPid)" 2>/dev/null; do
            sleep 0.2
            WAIT_COUNT=$((WAIT_COUNT + 1))
            if [ $WAIT_COUNT -ge 15 ]; then
                kill -9 "\(currentPid)" 2>/dev/null || true
                break
            fi
        done

        # 2. Descomprimir el ZIP
        rm -rf "\(extractDir)"
        mkdir -p "\(extractDir)"
        ditto -x -k "\(zipURL.path)" "\(extractDir)"

        # 3. Localizar el nuevo bundle .app
        NEW_APP=$(find "\(extractDir)" -name "*.app" -maxdepth 2 | head -n 1)

        if [ -d "$NEW_APP" ]; then
            # 4. Reemplazar la aplicación existente
            rm -rf "\(currentAppPath)"
            cp -R "$NEW_APP" "\(currentAppPath)"
            
            # 5. Eliminar atributos de cuarentena de Gatekeeper si aplica
            xattr -dr com.apple.quarantine "\(currentAppPath)" 2>/dev/null || true
            
            # 6. Lanzar la aplicación actualizada
            open "\(currentAppPath)"
        fi

        # 7. Limpiar temporales
        rm -rf "\(extractDir)" "\(zipURL.path)"
        """

        let scriptURL = URL(fileURLWithPath: "\(updatesDir)/relaunch_and_update.sh")
        try trampolineScript.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Dar permisos de ejecución
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptURL.path]
        try chmod.run()
        chmod.waitUntilExit()

        // Ejecutar el script desacoplado
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        try launcher.run()

        // Terminar la app para que el script pueda sustituirla.
        // En macOS con ventanas modales activas, NSApp.terminate() puede
        // quedar diferido por el runloop. exit(0) garantiza el cierre inmediato.
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
            exit(0)
        }
    }

    // MARK: - Utilidades SemVer

    /// Shared releases also contain a Windows ZIP; asset order is not a platform contract.
    nonisolated static func macOSDownloadURL(in assets: [[String: Any]]) -> URL? {
        assets.lazy.compactMap { asset -> URL? in
            guard let name = asset["name"] as? String,
                  name.caseInsensitiveCompare("SideB-macOS.zip") == .orderedSame,
                  let download = asset["browser_download_url"] as? String,
                  let url = URL(string: download), url.scheme == "https", url.host != nil else { return nil }
            return url
        }.first
    }

    public nonisolated static func cleanVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
    }

    /// Compare the numeric app versions shipped in both bundles. Release labels
    /// (-beta.1) and build metadata (+build.13) do not identify a newer app version.
    public nonisolated static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        func numericComponents(_ raw: String) -> [UInt64]? {
            let base = cleanVersion(raw).prefix { $0 != "-" && $0 != "+" }
            let components = base.split(separator: ".", omittingEmptySubsequences: false)
            guard !components.isEmpty else { return nil }
            var values: [UInt64] = []
            for part in components {
                guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                      let value = UInt64(part) else { return nil }
                values.append(value)
            }
            return values
        }

        guard let parts1 = numericComponents(v1), let parts2 = numericComponents(v2) else { return false }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}

// MARK: - URLSessionDownloadDelegate para el progreso

extension UpdateService: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.state = .downloading(progress: progress)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Mover a un archivo temporal antes de que el sistema lo borre
        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        do {
            try FileManager.default.moveItem(at: location, to: tempDestination)
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: tempDestination)
                self.downloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }
}
