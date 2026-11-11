import AppKit
import CoreImage

/// Lavado de la tarjeta de colección «teñida»: la carátula espejada en vertical y muy desenfocada
/// (CSS `blur(26px) saturate(1.5)` sobre la miniatura). Se genera una sola vez por carátula, fuera del hilo
/// principal y a baja resolución; la capa de la celda sólo muestra el resultado. Caché LRU acotada por URL y sesión;
/// las cargas en curso de la misma URL se comparten.
@MainActor
final class HomeCoverWashStore {
    static let shared = HomeCoverWashStore()
    static let capacity = 64
    /// Lado del bitmap resultante: basta porque el desenfoque deja sólo colores suaves.
    nonisolated static let side = 64

    private struct Entry {
        let value: CGImage?
        var lastAccess: UInt64
    }

    private struct Pending {
        let token: UInt64
        let task: Task<CGImage?, Never>
    }

    private var session: String?
    private var entries: [String: Entry] = [:]
    private var pending: [String: Pending] = [:]
    private var clock: UInt64 = 0
    private var nextToken: UInt64 = 0
    private(set) var renderCount = 0

    init() {}

    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Espeja, reduce, desenfoca y satura. Puro y sin estado: se llama fuera del hilo principal.
    nonisolated static func render(_ source: CGImage) -> CGImage? {
        let side = CGFloat(Self.side)
        var image = CIImage(cgImage: source)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        // Cuadrado central a `side`×`side`.
        let scale = side / min(extent.width, extent.height)
        image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY).scaledBy(x: scale, y: scale))
        let crop = CGRect(x: (image.extent.width - side) / 2, y: (image.extent.height - side) / 2, width: side, height: side)
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        // Espejado vertical.
        image = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -side))
        // 26 px de desenfoque (sigma 13) sobre ~360 pt de panel equivale a ~3 px en 64 px.
        image = image.clampedToExtent().applyingGaussianBlur(sigma: 3.1).cropped(to: rect)
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(image, forKey: kCIInputImageKey)
        controls.setValue(1.5, forKey: kCIInputSaturationKey)
        guard let output = controls.outputImage?.cropped(to: rect) else { return nil }
        return context.createCGImage(output, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// `nil` = aún no calculado; `.some(nil)` = calculado sin resultado (o fallo recordado).
    func cached(url: String, session: String) -> CGImage?? {
        adopt(session)
        guard var entry = entries[url] else { return nil }
        clock &+= 1
        entry.lastAccess = clock
        entries[url] = entry
        return .some(entry.value)
    }

    /// Lavado de la carátula; `nil` si no hay URL o falla. Nunca lanza.
    func wash(url: String?, session: String, image: @escaping @Sendable () async -> CGImage?) async -> CGImage? {
        guard let url else { return nil }
        if let hit = cached(url: url, session: session) { return hit }
        if let running = pending[url] { return await running.task.value }

        nextToken &+= 1
        let token = nextToken
        renderCount += 1
        let task = Task { [weak self] () -> CGImage? in
            let value = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let cgImage = await image() else { return nil }
                return HomeCoverWashStore.render(cgImage)
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

    private func finish(url: String, session resolvedSession: String, token: UInt64, value: CGImage?) {
        guard session == resolvedSession, pending[url]?.token == token else { return }
        pending[url] = nil
        clock &+= 1
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
