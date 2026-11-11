import AppKit
import CoreGraphics

/// Color por carátula para el degradado inferior de las celdas del mosaico (paridad con `coverColor.ts`).
/// Caché LRU por URL atada a una sesión; las cargas en curso de la misma URL se comparten.
@MainActor
final class HomeCoverColorStore {
    static let shared = HomeCoverColorStore()
    static let capacity = 128

    private struct Entry {
        let value: HomeAmbientRGB?
        var lastAccess: UInt64
    }

    private struct Pending {
        let token: UInt64
        let task: Task<HomeAmbientRGB?, Never>
    }

    private var session: String?
    private var entries: [String: Entry] = [:]
    private var pending: [String: Pending] = [:]
    private var clock: UInt64 = 0
    private var nextToken: UInt64 = 0

    init() {}

    // MARK: Funciones puras (utilizables fuera del hilo principal)

    /// Color más cromático de la paleta muestreada, con el tratamiento de ambiente; `nil` si no hay color utilizable.
    nonisolated static func dominantColor(rgba: [UInt8]) -> HomeAmbientRGB? {
        let palette = HomeAmbientPaletteSampler.tints(rgba: rgba)
        guard var best = palette.first else { return nil }
        for tint in palette.dropFirst() where tint.chroma > best.chroma { best = tint }
        return ambientTreated(best)
    }

    /// Reduce la imagen a 32×32 RGBA (8 bits, premultiplicado, bytes R,G,B,A) y calcula el color dominante.
    nonisolated static func sample(image: CGImage) -> HomeAmbientRGB? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drew ? dominantColor(rgba: pixels) : nil
    }

    /// Port de `ambientColor` (ambient.ts). `HomeAmbientRGB.ambientColor` ya hace lo mismo pero devuelve
    /// `Color` de SwiftUI, no componentes; aquí hacen falta componentes, así que se repite la fórmula.
    private nonisolated static func ambientTreated(_ rgb: HomeAmbientRGB) -> HomeAmbientRGB {
        let maximum = max(rgb.red, rgb.green, rgb.blue)
        let minimum = min(rgb.red, rgb.green, rgb.blue)
        let chroma = maximum - minimum
        guard chroma > 0.08 else { return rgb }
        let saturation = min(0.78, max(0.48, chroma / max(maximum, 0.001)))
        let low = 0.8 * (1 - saturation)
        func lift(_ component: Double) -> Double { low + (component - minimum) / chroma * (0.8 - low) }
        return HomeAmbientRGB(red: lift(rgb.red), green: lift(rgb.green), blue: lift(rgb.blue))
    }

    // MARK: Caché

    /// `nil` = aún no calculado; `.some(nil)` = calculado sin color (o fallo recordado).
    func cached(url: String, session: String) -> HomeAmbientRGB?? {
        adopt(session)
        guard var entry = entries[url] else { return nil }
        clock &+= 1
        entry.lastAccess = clock
        entries[url] = entry
        return .some(entry.value)
    }

    /// Color de la carátula; `nil` si no hay URL, falla la carga o no hay color. Nunca lanza.
    func color(url: String?, session: String,
               image: @escaping @Sendable () async -> CGImage?) async -> HomeAmbientRGB? {
        guard let url else { return nil }
        if let hit = cached(url: url, session: session) { return hit }
        if let running = pending[url] { return await running.task.value }

        nextToken &+= 1
        let token = nextToken
        let task = Task { [weak self] () -> HomeAmbientRGB? in
            let value = await Task.detached(priority: .utility) { () -> HomeAmbientRGB? in
                guard let cgImage = await image() else { return nil }
                return HomeCoverColorStore.sample(image: cgImage)
            }.value
            self?.finish(url: url, session: session, token: token, value: value)
            return value
        }
        pending[url] = Pending(token: token, task: task)
        return await task.value
    }

    func reset() {
        entries.removeAll()
        pending.removeAll()
        session = nil
        clock = 0
    }

    private func finish(url: String, session resolvedSession: String, token: UInt64, value: HomeAmbientRGB?) {
        // Si la sesión cambió mientras se resolvía, `pending` ya fue vaciado y el resultado no se guarda.
        guard session == resolvedSession, pending[url]?.token == token else { return }
        pending[url] = nil
        clock &+= 1
        // Un fallo también se recuerda (como nil) para no repetir pedidos al reciclar celdas.
        entries[url] = Entry(value: value, lastAccess: clock)
        while entries.count > Self.capacity,
              let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    private func adopt(_ newSession: String) {
        guard session != newSession else { return }
        entries.removeAll()
        pending.removeAll()
        clock = 0
        session = newSession
    }
}

extension HomeAmbientRGB {
    var nsColor: NSColor {
        NSColor(srgbRed: min(1, max(0, red)), green: min(1, max(0, green)),
                blue: min(1, max(0, blue)), alpha: 1)
    }

    var cgColor: CGColor { nsColor.cgColor }
}

/// Velo inferior del título sobre la portada: `color-mix(in srgb, cover 30%, #0b0b0f)` y sus paradas.
enum HomeCoverScrim {
    /// Color de la carátula cuando no hay uno utilizable (#101014).
    static let fallbackCover = HomeAmbientRGB(red: 16.0 / 255, green: 16.0 / 255, blue: 20.0 / 255)
    private static let base = (red: 11.0 / 255, green: 11.0 / 255, blue: 15.0 / 255)

    /// `0.3·cover + 0.7·#0b0b0f` por canal, en sRGB.
    static func color(cover: HomeAmbientRGB?) -> HomeAmbientRGB {
        let source = cover ?? fallbackCover
        return HomeAmbientRGB(red: 0.3 * source.red + 0.7 * base.red,
                              green: 0.3 * source.green + 0.7 * base.green,
                              blue: 0.3 * source.blue + 0.7 * base.blue)
    }

    /// De abajo hacia arriba: posición (0 = borde inferior, 1 = superior) y alfa.
    static let stops: [(location: Double, alpha: Double)] = [
        (0.00, 0.94), (0.20, 0.80), (0.42, 0.48), (0.66, 0.14), (1.00, 0.00)
    ]
}
