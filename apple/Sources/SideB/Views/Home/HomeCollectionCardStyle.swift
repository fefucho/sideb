import AppKit

/// Medidas de la tarjeta grande de colección (reglas `.panel` de MediaCard.svelte).
enum HomeCollectionCardMetrics {
    static let cornerRadius: CGFloat = 14
    static let paddingTop: CGFloat = 12
    static let paddingSide: CGFloat = 14
    static let paddingBottom: CGFloat = 14
    static let badgeHeight: CGFloat = 14
    static let badgeBottom: CGFloat = 2
    static let titleHeight: CGFloat = 22
    static let artistHeight: CGFloat = 19
    static let summaryGap: CGFloat = 6
    static let summaryHeight: CGFloat = 32
    /// 12 + 14 + 2 + 22 + 19 + 6 + 32 + 14.
    static let panelHeight: CGFloat = paddingTop + badgeHeight + badgeBottom + titleHeight
        + artistHeight + summaryGap + summaryHeight + paddingBottom
    /// Aire dentro de la fila para la elevación y la sombra: arriba 8 y abajo 48.
    static let airTop: CGFloat = 8
    static let airBottom: CGFloat = 48
    static let lift: CGFloat = 4
    static let controlDiameter: CGFloat = 38
    static let controlInset: CGFloat = 12
    static let controlIcon: CGFloat = 20
    static let washBleed: CGFloat = 34
    static let hoverDuration: CFTimeInterval = 0.18
    static let dimDuration: CFTimeInterval = 0.15
    static let dimOpacity: Float = 0.3

    static func cardHeight(cardWidth: CGFloat) -> CGFloat { cardWidth + panelHeight }
    /// Alto del carril: la tarjeta más el aire de la sombra.
    static func railHeight(cardWidth: CGFloat) -> CGFloat { cardHeight(cardWidth: cardWidth) + airTop + airBottom }

    /// Sombra CSS `0 dy blur −spread` negra: `blur / 2` es el radio de la capa y la dispersión negativa encoge el
    /// rectángulo. El desplazamiento se hornea en el camino (el eje Y de la capa depende de la orientación de la vista).
    struct Shadow: Equatable {
        let inset: CGFloat
        let offset: CGFloat
        let radius: CGFloat
        let opacity: Float
    }
    /// `0 12px 30px -16px #000`.
    static let restShadow = Shadow(inset: 16, offset: 12, radius: 15, opacity: 1)
    /// `0 20px 34px -18px rgb(0 0 0 / 80%)`: siempre negra, nunca del color de la carátula.
    static let liftedShadow = Shadow(inset: 18, offset: 20, radius: 17, opacity: 0.8)
}

/// Colores fijos del panel (no semánticos: es claro también con el sistema en modo oscuro).
struct HomeCollectionCardPalette: Equatable {
    let panel: NSColor
    let title: NSColor
    let artist: NSColor
    let artistHover: NSColor
    let muted: NSColor
    /// Si el acabado lleva la portada desenfocada detrás del texto.
    let washed: Bool

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    static func make(_ style: HomeAlbumCardStyle) -> Self {
        switch style {
        case .white:
            Self(panel: hex(0xf5f5f7), title: hex(0x1d1d1f), artist: hex(0x3a3a3c), artistHover: .black,
                 muted: hex(0x6e6e73), washed: false)
        case .tinted:
            Self(panel: hex(0xf5f5f7), title: hex(0x1d1d1f), artist: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.79),
                 artistHover: .black, muted: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.58), washed: true)
        }
    }

    /// Velo blanco que cubre la portada desenfocada.
    static let veil = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.78)
}

/// Etiqueta de tipo de la tarjeta, con la lógica de `albumCollectionType` y de MediaCard.svelte.
enum HomeCollectionBadge {
    enum ReleaseType: Equatable { case album, single, ep }

    /// Sólo cuenta un primer componente real del subtítulo del proveedor, nunca el número de canciones.
    static func releaseType(subtitle: String?) -> ReleaseType {
        let first = subtitle?.components(separatedBy: CharacterSet(charactersIn: "•·"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        switch first?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) {
        case "single", "sencillo": return .single
        case "ep": return .ep
        default: return .album
        }
    }

    /// Mismas claves y mayúsculas que Windows: «ÁLBUM» y «LISTA DE REPRODUCCIÓN» vienen en mayúsculas, «Sencillo» no.
    @MainActor static func text(kind: String, subtitle: String?) -> String {
        guard kind == "album" else { return L10n.text("detail.kind.playlist") }
        switch releaseType(subtitle: subtitle) {
        case .single: return L10n.text("metadata.single")
        case .ep: return "EP"
        case .album: return L10n.text("detail.kind.album")
        }
    }
}

/// Tarjetas de la fila que tocan el área útil (sin los márgenes), en el orden de la fila.
enum HomeCollectionRowViewport {
    static func visibleIDs(ids: [String], cardWidth: CGFloat, spacing: CGFloat, offset: CGFloat, width: CGFloat,
                           leadingInset: CGFloat, trailingInset: CGFloat) -> [String] {
        guard width > 0, cardWidth > 0 else { return [] }
        let stride = cardWidth + spacing
        return ids.enumerated().compactMap { index, id in
            let from = leadingInset + CGFloat(index) * stride - offset
            return from + cardWidth > leadingInset + 1 && from < width - trailingInset - 1 ? id : nil
        }
    }
}

/// Orden del pedido de detalles: las tarjetas a la vista primero y después el resto, en el orden de la fila.
enum HomeCollectionRequestOrder {
    static func order<Element>(_ items: [Element], visible: [String], id: (Element) -> String) -> [Element] {
        let shown = Set(visible)
        return items.filter { shown.contains(id($0)) } + items.filter { !shown.contains(id($0)) }
    }
}

/// Encaje al inicio de tarjeta al terminar un desplazamiento (`scroll-snap-type: x proximity`).
enum HomeCollectionRowSnap {
    /// Fracción del paso a la que todavía se considera «cerca» del inicio de una tarjeta.
    static let proximity: CGFloat = 0.3

    /// El desplazamiento al que acomodarse, o `nil` si queda lejos de todo inicio de tarjeta.
    static func target(offset: CGFloat, stride: CGFloat, maximum: CGFloat) -> CGFloat? {
        guard stride > 0, maximum > 0 else { return nil }
        let clamped = min(max(0, offset), maximum)
        let start = min(maximum, max(0, (clamped / stride).rounded() * stride))
        let distance = abs(start - clamped)
        return distance > 0.5 && distance <= stride * proximity ? start : nil
    }
}

/// Seguimiento de las tarjetas visibles que publica el carril (sin estado de SwiftUI: publicar no vuelve a pintar).
/// El pedido de detalles espera a la primera publicación, que llega justo después del primer layout, y así sabe
/// qué tarjetas van primero aunque la fila se haya restaurado lejos del inicio.
@MainActor
final class HomeVisibleCollectionTracker {
    private(set) var ids: [String]?
    private var waiters: [UUID: CheckedContinuation<[String], Never>] = [:]

    func publish(_ ids: [String]) {
        self.ids = ids
        let pending = waiters
        waiters.removeAll()
        for continuation in pending.values { continuation.resume(returning: ids) }
    }

    /// Las visibles, esperando la primera publicación. Si la tarea se cancela devuelve vacío.
    func firstPublication() async -> [String] {
        if let ids { return ids }
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let ids { continuation.resume(returning: ids) } else { waiters[token] = continuation }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(token) }
        }
    }

    private func cancel(_ token: UUID) {
        waiters.removeValue(forKey: token)?.resume(returning: [])
    }
}
