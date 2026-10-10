import Foundation
import Testing
@testable import SideB

@Suite("Tests de Auto-Actualizador (UpdateService)")
struct UpdateServiceTests {

    @Test("Release compartido: Mac elige su ZIP independientemente del orden")
    func testMacDownloadFromMixedPlatformAssets() {
        let mac = ["name": "SideB-macOS.zip", "browser_download_url": "https://example.com/SideB-macOS.zip"]
        let windows = ["name": "SideB-Windows-x64.zip", "browser_download_url": "https://example.com/SideB-Windows-x64.zip"]
        let checksum = ["name": "SideB-macOS-SHA256.txt", "browser_download_url": "https://example.com/checksums.txt"]
        for assets in [[windows, checksum, mac], [mac, windows, checksum], [mac]] {
            #expect(UpdateService.macOSDownloadURL(in: assets) == URL(string: mac["browser_download_url"]!))
        }
    }

    @Test("Release incompleto: no descargar Windows ni un destino inválido en Mac")
    func testMacDownloadRejectsMissingAndInvalidPackage() {
        for assets: [[String: Any]] in [[],
            [["name": "SideB-Windows-x64.zip", "browser_download_url": "https://example.com/windows.zip"]],
            [["name": "SideB-macOS.zip"]],
            [["name": "SideB-macOS.zip", "browser_download_url": "file:///tmp/mac.zip"]],
            [["name": "SideB-macOS.zip", "browser_download_url": "mac.zip"]]
        ] {
            #expect(UpdateService.macOSDownloadURL(in: assets) == nil)
        }
    }

    @Test("Limpieza de prefijos de versión (v / V / espacios)")
    func testCleanVersion() {
        #expect(UpdateService.cleanVersion("v1.0.1") == "1.0.1")
        #expect(UpdateService.cleanVersion("V2.3.4") == "2.3.4")
        #expect(UpdateService.cleanVersion("  v1.5.0  \n") == "1.5.0")
        #expect(UpdateService.cleanVersion("1.0.0") == "1.0.0")
        #expect(UpdateService.cleanVersion("v1.2.0-beta.1+build.13") == "1.2.0-beta.1+build.13")
    }

    @Test("Comparación SemVer: versión mayor")
    func testMajorVersion() {
        #expect(UpdateService.isVersion("2.0.0", newerThan: "1.9.9"))
        #expect(!UpdateService.isVersion("1.0.0", newerThan: "2.0.0"))
    }

    @Test("Comparación SemVer: versión menor")
    func testMinorVersion() {
        #expect(UpdateService.isVersion("1.2.0", newerThan: "1.1.9"))
        #expect(!UpdateService.isVersion("1.1.0", newerThan: "1.2.0"))
    }

    @Test("Comparación SemVer: versión patch")
    func testPatchVersion() {
        #expect(UpdateService.isVersion("1.0.1", newerThan: "1.0.0"))
        #expect(UpdateService.isVersion("v1.0.2", newerThan: "1.0.1"))
        #expect(!UpdateService.isVersion("1.0.0", newerThan: "1.0.1"))
    }

    @Test("Comparación SemVer: igualdad")
    func testEqualVersion() {
        #expect(!UpdateService.isVersion("1.0.0", newerThan: "1.0.0"))
        #expect(!UpdateService.isVersion("v1.0.0", newerThan: "1.0.0"))
        #expect(!UpdateService.isVersion("1.0", newerThan: "1.0.0"))
    }

    @Test("Comparación SemVer: longitud de segmentos heterogénea")
    func testUnequalSegmentLength() {
        #expect(UpdateService.isVersion("1.0.1", newerThan: "1.0"))
        #expect(!UpdateService.isVersion("1.0", newerThan: "1.0.1"))
        #expect(UpdateService.isVersion("1.1", newerThan: "1.0.5"))
        #expect(UpdateService.isVersion("1.0.0.1", newerThan: "1.0.0"))
    }

    @Test("Un tag beta o metadata de build no vuelve a ofrecer la versión instalada")
    func testReleaseLabelsDoNotOfferInstalledVersionAgain() {
        for remote in ["v1.2.0-beta.1", "1.2.0-beta.999", "V1.2.0-rc.99", "1.2.0+build.999", "1.2.0-beta.1+build.13"] {
            #expect(!UpdateService.isVersion(remote, newerThan: "1.2.0"))
            #expect(!UpdateService.isVersion("1.2.0", newerThan: remote))
        }
    }

    @Test("Los calificadores conservan actualizaciones reales y rechazan versiones anteriores")
    func testLabelsPreserveRealUpdates() {
        for (remote, current, expected) in [
            ("v1.2.0-beta.1", "1.1.8", true),
            ("v1.2.1-beta.1", "1.2.0", true),
            ("1.3.0-beta.1", "1.2.9", true),
            ("1.2.0-beta.999", "1.2.1", false),
            ("1.2.0+build.999", "1.2.1", false),
            ("v1.1.9-beta.999", "1.2.0", false)
        ] {
            #expect(UpdateService.isVersion(remote, newerThan: current) == expected)
        }
    }

    @Test("Una versión inválida no se reconstruye descartando segmentos")
    func testMalformedVersionsDoNotTriggerUpdate() {
        for invalid in ["", "garbage", "1..2", "1.beta.999", "1.2.3trailing", "1.-2.0", "-1.2.0", "18446744073709551616.0.0"] {
            #expect(!UpdateService.isVersion(invalid, newerThan: "1.2.0"))
            #expect(!UpdateService.isVersion("1.2.1", newerThan: invalid))
        }
    }

    @Test("Omitir versión: suprime notificación en comprobación automática")
    @MainActor
    func testSkippedVersionSuppression() {
        let service = UpdateService()
        service.skippedVersion = "1.0.6"
        #expect(!service.shouldNotifyUser(for: "1.0.6", manual: false))
        service.resetSkippedVersion()
    }

    @Test("Omitir versión: búsqueda manual siempre notifica aunque esté omitida")
    @MainActor
    func testSkippedVersionOverridesOnManualCheck() {
        let service = UpdateService()
        service.skippedVersion = "1.0.6"
        #expect(service.shouldNotifyUser(for: "1.0.6", manual: true))
        service.resetSkippedVersion()
    }

    @Test("Omitir versión: una versión más nueva notifica automáticamente")
    @MainActor
    func testNewerVersionOverridesPreviousSkip() {
        let service = UpdateService()
        service.skippedVersion = "1.0.6"
        #expect(service.shouldNotifyUser(for: "1.0.7", manual: false))
        service.resetSkippedVersion()
    }

    @Test("Método skipVersion persiste valor y resetea estado")
    @MainActor
    func testSkipVersionMethodAndReset() {
        let service = UpdateService()
        service.isSheetPresented = true
        service.state = .available(ReleaseInfo(
            tagName: "v2.0.0",
            version: "2.0.0",
            releaseNotes: "Notas",
            downloadURL: URL(string: "https://example.com/app.zip")!,
            publishedAt: nil
        ))

        service.skipVersion("2.0.0")
        #expect(service.skippedVersion == "2.0.0")
        #expect(!service.isSheetPresented)
        #expect(service.state == .idle)

        service.resetSkippedVersion()
        #expect(service.skippedVersion == nil)
    }
}
