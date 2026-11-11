import AppKit
import QuartzCore

/// Círculo de Play/menú de la tarjeta de colección: vidrio sobre la portada.
/// Con Reduce Transparency es un círculo opaco negro al 60 % sin desenfoque. Nunca recibe clics:
/// los controles reales son los botones transparentes de `HomeItemView`.
final class HomeGlassCircleView: NSView {
    /// Opaco sin desenfoque (Reduce Transparency).
    let isSolid: Bool
    private let tint = CALayer()
    private var backdrop: NSView?

    var highlighted = false { didSet { if highlighted != oldValue { applyTint() } } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(solid: Bool) {
        isSolid = solid
        super.init(frame: NSRect(x: 0, y: 0, width: HomeCollectionCardMetrics.controlDiameter,
                                 height: HomeCollectionCardMetrics.controlDiameter))
        wantsLayer = true
        layer?.masksToBounds = true
        if !solid {
            // Liquid Glass donde existe (macOS 26+); debajo, el mismo desenfoque que usa la barra superior.
            let backdrop: NSView
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: bounds)
                glass.style = .regular
                backdrop = glass
            } else {
                let effect = NSVisualEffectView(frame: bounds)
                effect.material = .hudWindow
                effect.blendingMode = .withinWindow
                effect.state = .active
                backdrop = effect
            }
            backdrop.autoresizingMask = [.width, .height]
            addSubview(backdrop)
            self.backdrop = backdrop
        }
        layer?.addSublayer(tint)
        applyTint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    var hasBlurForTesting: Bool { backdrop != nil }

    /// Alfa del velo blanco que aclara el vidrio; en reposo y bajo el puntero (Windows: 22 % y 34 %).
    var tintAlphaForTesting: CGFloat { tintAlpha }
    private var tintAlpha: CGFloat {
        if isSolid { return highlighted ? 0.25 : 0 }
        if #available(macOS 26.0, *) { return highlighted ? 0.22 : 0.06 }
        return highlighted ? 0.34 : 0.22
    }

    private func applyTint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isSolid {
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            tint.backgroundColor = NSColor.white.withAlphaComponent(tintAlpha).cgColor
        } else {
            tint.backgroundColor = NSColor.white.withAlphaComponent(tintAlpha).cgColor
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.width / 2
        tint.frame = bounds
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView { glass.cornerRadius = bounds.width / 2 }
        CATransaction.commit()
    }
}

/// Fondo del panel de texto: color base, la portada desenfocada con su velo blanco (acabado teñido) y las
/// esquinas inferiores de la tarjeta. La portada sobresale 34 pt por lado para que no se vean los bordes del desenfoque.
final class HomeCollectionPanelView: NSView {
    private let surface = CALayer()
    private let wash = CALayer()
    private let veil = CALayer()
    private(set) var washImage: CGImage?
    var surfaceColor: CGColor? { surface.backgroundColor }
    var surfaceFrame: CGRect { surface.frame }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // El panel recorta recto; `surface` se alarga un radio hacia arriba con las cuatro esquinas
        // redondeadas, así sólo se ven redondas las de abajo y la unión con la portada queda recta.
        // No se usa `maskedCorners`: su eje depende del volteo heredado y el render fuera de pantalla lo ignora.
        layer?.masksToBounds = true
        surface.masksToBounds = true
        surface.cornerRadius = HomeCollectionCardMetrics.cornerRadius
        wash.contentsGravity = .resizeAspectFill
        wash.magnificationFilter = .linear
        wash.isHidden = true
        veil.isHidden = true
        layer?.addSublayer(surface)
        surface.addSublayer(wash)
        surface.addSublayer(veil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func apply(palette: HomeCollectionCardPalette) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.backgroundColor = palette.panel.cgColor
        veil.backgroundColor = HomeCollectionCardPalette.veil.cgColor
        CATransaction.commit()
        updateWashVisibility(palette: palette)
    }

    private var washed = false
    private func updateWashVisibility(palette: HomeCollectionCardPalette) {
        washed = palette.washed
        let show = washed && washImage != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.isHidden = !show
        veil.isHidden = !show
        CATransaction.commit()
    }

    func setWash(_ image: CGImage?) {
        washImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.contents = image
        let show = washed && image != nil
        wash.isHidden = !show
        veil.isHidden = !show
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bleed = HomeCollectionCardMetrics.washBleed
        let radius = HomeCollectionCardMetrics.cornerRadius
        // Subcapas de una vista volteada: el eje Y crece hacia abajo, así que y negativo es hacia arriba.
        surface.frame = CGRect(x: 0, y: -radius, width: bounds.width, height: bounds.height + radius)
        wash.frame = CGRect(x: -bleed, y: radius - bleed, width: bounds.width + 2 * bleed, height: bounds.height + 2 * bleed)
        veil.frame = surface.bounds
        CATransaction.commit()
    }
}
