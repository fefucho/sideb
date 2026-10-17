import AppKit
import CoreImage
import Metal
import QuartzCore
import SwiftUI

/// A scalar component of the existing ambient motion. Independent periods avoid
/// a large shared repeat cycle. Linear interpolation at30Hz has a bounded error.
struct HomeAmbientWave: Equatable {
    static let sampleRate: Double = 30
    let base: Double
    let amplitude: Double
    let period: Double
    var phase: Double = 0
    var isCosine = false

    func value(at time: TimeInterval) -> Double {
        let angle = time * 2 * .pi / period + phase
        return base + amplitude * (isCosine ? cos(angle) : sin(angle))
    }

    func samples(startingAt time: TimeInterval) -> [Double] {
        let count = max(1, Int(ceil(period * Self.sampleRate)))
        var result = (0...count).map { value(at: time + Double($0) * period / Double(count)) }
        // Mathematically these endpoints coincide; use the same floating-point
        // value at the repeat seam rather than carrying large-epoch roundoff.
        result[count] = result[0]
        return result
    }

    var maximumInterpolationError: Double {
        let step = period / Double(max(1, Int(ceil(period * Self.sampleRate))))
        return abs(amplitude) * pow(2 * .pi / period * step, 2) / 8
    }
}

struct HomeAmbientLayerGeometry: Equatable {
    let cloudCenters: [CGPoint]
    let cloudRadii: [CGFloat]
    let smokeOffsets: [CGPoint]
    let smokeAngles: [CGFloat]
    let smokeScales: [CGSize]

    init(size: CGSize, time: TimeInterval) {
        // Keep the original operation order for deterministic snapshots at
        // large reference-date values; regrouping a*0.8 changes floating-point
        // rounding even though the periodic animation is mathematically equal.
        cloudCenters = [(0.06, 0.02, 42.0, 0.11, 0.0),
                        (0.94, 0.18, 50.0, 0.11, 2.0),
                        (0.43, 0.73, 36.0, 0.15, 4.0)].map { x, y, period, amount, phase in
            let angle = time * 2 * .pi / period + phase
            return CGPoint(x: (x + sin(angle) * amount) * size.width,
                           y: (y + cos(angle * 0.8) * amount) * size.height)
        }
        cloudRadii = [0.62, 0.58, 0.42].map { max(size.width, size.height) * $0 }
        let smoke = Self.smokeWaves(size: size)
        smokeOffsets = smoke.map { CGPoint(x: $0.x.value(at: time), y: $0.y.value(at: time)) }
        smokeAngles = smoke.map { CGFloat($0.rotation.value(at: time)) }
        smokeScales = [CGSize(width: 1.5, height: 1.5), CGSize(width: -1.75, height: 1.75)]
    }

    static func cloudWaves(size: CGSize) -> [(x: HomeAmbientWave, y: HomeAmbientWave)] {
        [(0.06, 0.02, 42.0, 0.11, 0.0),
         (0.94, 0.18, 50.0, 0.11, 2.0),
         (0.43, 0.73, 36.0, 0.15, 4.0)].map { x, y, period, amount, phase in
            (HomeAmbientWave(base: x * size.width, amplitude: amount * size.width, period: period, phase: phase),
             HomeAmbientWave(base: y * size.height, amplitude: amount * size.height, period: period / 0.8,
                             phase: phase * 0.8, isCosine: true))
        }
    }

    static func smokeWaves(size: CGSize) -> [(x: HomeAmbientWave, y: HomeAmbientWave, rotation: HomeAmbientWave)] {
        [(HomeAmbientWave(base: 0, amplitude: size.width * 0.11, period: 45),
          HomeAmbientWave(base: 0, amplitude: size.height * 0.06, period: 56, isCosine: true),
          HomeAmbientWave(base: 0, amplitude: 3.5 * .pi / 180, period: 70)),
         (HomeAmbientWave(base: 0, amplitude: size.width * 0.14, period: 65, phase: 1, isCosine: true),
          HomeAmbientWave(base: 0, amplitude: size.height * 0.08, period: 78, phase: 2),
          HomeAmbientWave(base: 0, amplitude: 4.5 * .pi / 180, period: 88, isCosine: true))]
    }
}

/// The SwiftUI bridge only delivers semantic changes and viewport geometry.
/// Display callbacks only submit the isolated layer tree to Metal. They never
/// enter SwiftUI or call setNeedsDisplay/layout on the window's view tree.
struct HomeAmbientLayerView: NSViewRepresentable {
    let palette: HomeAmbientPalette
    let smokeMask: CGImage?
    let isObscured: Bool
    let reduceMotion: Bool
    let scenePhase: ScenePhase
    @Environment(\.displayScale) private var displayScale

    func makeNSView(context: Context) -> HomeAmbientLayerNSView {
        let view = HomeAmbientLayerNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: HomeAmbientLayerNSView, context: Context) {
        let animated = !reduceMotion && !context.transaction.disablesAnimations && context.transaction.animation != nil
        view.configure(palette: palette, smokeMask: smokeMask,
            active: !isObscured && scenePhase == .active, reduceMotion: reduceMotion, displayScale: displayScale,
            paletteDuration: animated ? 1 : 0, smokeDuration: animated ? 0.5 : 0)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HomeAmbientLayerNSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }

    static func dismantleNSView(_ view: HomeAmbientLayerNSView, coordinator: ()) { view.releaseContent() }
}

@MainActor
final class HomeAmbientLayerNSView: NSView {
    // Core Image must not enter the NSWindow layer hierarchy: enabling
    // layerUsesCoreImageFilters there also changes how sibling SwiftUI/Glass
    // layers are rendered. CARenderer owns a separate tree, and AppKit only
    // sees the resulting Metal surface.
    let renderLayer = CALayer()
    private let canvas = CALayer()
    private let metalLayer = CAMetalLayer()
    private var renderer: CARenderer?
    private var commandQueue: (any MTLCommandQueue)?
    private var frameLink: CADisplayLink?
    private var frameTarget: FrameTarget?
    private let framesInFlight = DispatchSemaphore(value: 2)
    private var dirtyFrame = true
    private let baseLayer = CALayer()
    private let clouds = (0..<3).map { _ in CAGradientLayer() }
    private let smoke = (0..<2).map { _ in SmokeLayers() }
    private let veil = CAGradientLayer()
    private var clock: HomeAmbientMotionClock
    private var fixedTime: TimeInterval?
    private var palette: HomeAmbientPalette?
    private var mask: CGImage?
    private var active = false
    private var reduceMotion = false
    private var scale: CGFloat = 1
    private var renderedSize = CGSize.zero
    private var moving = false
    private var hasBeenInWindow = false
    private var occlusionObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    init(frame frameRect: NSRect = .zero,
         initialTime: TimeInterval = Date.timeIntervalSinceReferenceDate,
         fixedTime: TimeInterval? = nil) {
        clock = HomeAmbientMotionClock(time: initialTime)
        self.fixedTime = fixedTime
        super.init(frame: frameRect)
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.maximumDrawableCount = 3
        metalLayer.isOpaque = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.backgroundColor = NSColor(srgbRed: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 1).cgColor
        commandQueue = metalLayer.device?.makeCommandQueue()
        layer = metalLayer
        wantsLayer = true
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        // Match the former flipped NSView backing layer at the root of the
        // isolated tree, including CARenderer's texture orientation.
        renderLayer.isGeometryFlipped = true
        canvas.isGeometryFlipped = true
        canvas.masksToBounds = true
        renderLayer.addSublayer(canvas)
        baseLayer.backgroundColor = NSColor(srgbRed: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 1).cgColor
        canvas.addSublayer(baseLayer)
        for cloud in clouds {
            cloud.type = .radial
            cloud.startPoint = CGPoint(x: 0.5, y: 0.5)
            cloud.endPoint = CGPoint(x: 1, y: 1)
            cloud.locations = [0, 0.32, 0.70, 1]
            cloud.compositingFilter = HomeAmbientScreenFilter.make()
            canvas.addSublayer(cloud)
        }
        for smoke in smoke { canvas.addSublayer(smoke.offset) }
        veil.startPoint = CGPoint(x: 0.5, y: 0)
        veil.endPoint = CGPoint(x: 0.5, y: 1)
        veil.locations = [0, 0.42, 1]
        veil.colors = [NSColor.black.withAlphaComponent(0).cgColor,
                       NSColor.black.withAlphaComponent(0.08).cgColor,
                       NSColor.black.withAlphaComponent(0.46).cgColor]
        canvas.addSublayer(veil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    deinit {
        frameLink?.invalidate()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    func configure(palette: HomeAmbientPalette, smokeMask: CGImage?, active: Bool, reduceMotion: Bool,
                   displayScale: CGFloat, paletteDuration: TimeInterval = 0, smokeDuration: TimeInterval = 0,
                   at date: Date = Date()) {
        self.active = active
        let justReducedMotion = reduceMotion && !self.reduceMotion
        self.reduceMotion = reduceMotion
        if justReducedMotion {
            dirtyFrame = true
            // Model colors/opacity already hold their final values. Preference
            // changes must not leave a previously started fade in flight.
            clouds.forEach { $0.removeAnimation(forKey: "ambientPalette") }
            for smoke in smoke {
                smoke.gradient.removeAnimation(forKey: "ambientPalette")
                smoke.offset.removeAnimation(forKey: "smokeArrival")
            }
        }
        let nextScale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        if nextScale != scale {
            scale = nextScale
            allLayers.forEach { $0.contentsScale = nextScale }
            updateRenderTargetSize()
            dirtyFrame = true
        }
        if self.palette != palette {
            let duration = self.palette == nil || reduceMotion ? 0 : paletteDuration
            self.palette = palette
            applyPalette(palette, duration: duration)
            dirtyFrame = true
        }
        if mask !== smokeMask {
            let firstMask = mask == nil && smokeMask != nil
            mask = smokeMask
            dirtyFrame = true
            withoutActions {
                for smoke in smoke {
                    smoke.mask.contents = smokeMask
                    smoke.offset.isHidden = smokeMask == nil
                    smoke.offset.opacity = smokeMask == nil ? 0 : 1
                    if firstMask, !reduceMotion, smokeDuration > 0 {
                        let fade = CABasicAnimation(keyPath: "opacity")
                        fade.fromValue = 0
                        fade.toValue = 1
                        fade.duration = smokeDuration
                        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        smoke.offset.add(fade, forKey: "smokeArrival")
                    }
                }
            }
        }
        refreshMotion(at: date)
        scheduleFrameIfNeeded()
    }

    func motionTime(at date: Date = Date()) -> TimeInterval { fixedTime ?? clock.time(at: date) }

    func setFixedTime(_ time: TimeInterval?) {
        fixedTime = time
        refreshMotion(at: Date(), force: true)
        scheduleFrameIfNeeded()
    }

    override func layout() {
        super.layout()
        guard bounds.size != renderedSize else { return }
        renderedSize = bounds.size
        updateRenderTargetSize()
        refreshMotion(at: Date(), force: true)
        dirtyFrame = true
        scheduleFrameIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window {
            hasBeenInWindow = true
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in Task { @MainActor in
                self?.refreshMotion(at: Date())
                self?.scheduleFrameIfNeeded()
            } }
        }
        refreshMotion(at: Date())
        if window == nil {
            frameLink?.invalidate()
            frameLink = nil
            frameTarget = nil
        } else {
            dirtyFrame = true
            scheduleFrameIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { nil }

    func releaseContent() {
        active = false
        refreshMotion(at: Date())
        allLayers.forEach { $0.removeAllAnimations() }
        mask = nil
        palette = nil
        applyPalette(.neutral, duration: 0)
        smoke.forEach { $0.mask.contents = nil; $0.offset.isHidden = true }
        frameLink?.invalidate()
        frameLink = nil
        frameTarget = nil
        renderer?.layer = nil
        renderer = nil
        dirtyFrame = true
    }

    private var allLayers: [CALayer] {
        [renderLayer, canvas, baseLayer, veil] + clouds + smoke.flatMap { [$0.offset, $0.rotation, $0.gradient, $0.mask] }
    }

    private func refreshMotion(at date: Date, force: Bool = false) {
        // Scene activity comes from the same SwiftUI environment as before.
        // A visible window must not stop merely because another app has focus.
        let windowActive = window.map { $0.occlusionState.contains(.visible) } ?? !hasBeenInWindow
        let shouldMove = active && !reduceMotion && fixedTime == nil && windowActive
        let changed = moving != shouldMove
        clock.setRunning(shouldMove, at: date)
        moving = shouldMove
        guard changed || force else { return }
        let time = motionTime(at: date)
        applyGeometry(time: time)
        removeMotionAnimations()
        if shouldMove, renderedSize.width > 0, renderedSize.height > 0 { installMotionAnimations(time: time) }
        dirtyFrame = true
    }

    private func updateRenderTargetSize() {
        let pixels = CGSize(width: max(0, ceil(bounds.width * scale)), height: max(0, ceil(bounds.height * scale)))
        withoutActions {
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = pixels
            renderLayer.frame = CGRect(origin: .zero, size: pixels)
            canvas.position = CGPoint(x: pixels.width / 2, y: pixels.height / 2)
            canvas.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private var canPresent: Bool {
        window?.occlusionState.contains(.visible) == true && bounds.width > 0 && bounds.height > 0
    }

    private func scheduleFrameIfNeeded() {
        guard canPresent, commandQueue != nil else { frameLink?.isPaused = true; return }
        if frameLink == nil {
            let target = FrameTarget(owner: self)
            let link = displayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            frameTarget = target
            frameLink = link
        }
        frameLink?.isPaused = !needsPresentation
    }

    private var hasFades: Bool {
        clouds.contains { $0.animation(forKey: "ambientPalette") != nil } ||
            smoke.contains { $0.gradient.animation(forKey: "ambientPalette") != nil ||
                             $0.offset.animation(forKey: "smokeArrival") != nil }
    }

    var needsPresentation: Bool { moving || dirtyFrame || hasFades }

    func didSubmitFrame() {
        dirtyFrame = false
        scheduleFrameIfNeeded()
    }

    private func presentFrame(at time: CFTimeInterval) {
        guard canPresent, let commandQueue else {
            frameLink?.isPaused = true
            return
        }
        // Bound submitted GPU work and skip a tick if the queue is full.
        // nextDrawable itself may still wait for the display's drawable pool.
        guard framesInFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = metalLayer.nextDrawable(), let completion = commandQueue.makeCommandBuffer() else {
            framesInFlight.signal()
            return
        }
        if renderer == nil {
            renderer = CARenderer(mtlTexture: drawable.texture, options: [
                kCARendererMetalCommandQueue: commandQueue,
                kCARendererColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
            renderer?.layer = renderLayer
        }
        guard let renderer else { framesInFlight.signal(); return }
        renderer.setDestination(drawable.texture)
        renderer.bounds = renderLayer.bounds
        renderer.beginFrame(atTime: time, timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // The shared queue orders presentation after CARenderer's submitted
        // work without an explicit waitUntilCompleted on the main thread.
        completion.present(drawable)
        let semaphore = framesInFlight
        completion.addCompletedHandler { _ in semaphore.signal() }
        completion.commit()
        didSubmitFrame()
    }

    @MainActor private final class FrameTarget: NSObject {
        weak var owner: HomeAmbientLayerNSView?
        init(owner: HomeAmbientLayerNSView) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.presentFrame(at: link.targetTimestamp) }
    }

    private func applyGeometry(time: TimeInterval) {
        let geometry = HomeAmbientLayerGeometry(size: renderedSize, time: time)
        withoutActions {
            canvas.bounds = CGRect(origin: .zero, size: renderedSize)
            canvas.position = CGPoint(x: renderLayer.bounds.width / 2, y: renderLayer.bounds.height / 2)
            canvas.transform = CATransform3DMakeScale(scale, scale, 1)
            baseLayer.frame = canvas.bounds
            veil.frame = canvas.bounds
            for (index, cloud) in clouds.enumerated() {
                let radius = geometry.cloudRadii[index]
                cloud.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
                cloud.position = geometry.cloudCenters[index]
            }
            for (index, smoke) in smoke.enumerated() {
                smoke.offset.bounds = CGRect(origin: .zero, size: renderedSize)
                smoke.offset.position = CGPoint(x: renderedSize.width / 2 + geometry.smokeOffsets[index].x,
                                                y: renderedSize.height / 2 + geometry.smokeOffsets[index].y)
                smoke.rotation.bounds = smoke.offset.bounds
                smoke.rotation.position = CGPoint(x: renderedSize.width / 2, y: renderedSize.height / 2)
                // The layer's flipped coordinate ancestry reverses rotation
                // relative to SwiftUI's top-down rotationEffect.
                smoke.rotation.transform = CATransform3DMakeRotation(-geometry.smokeAngles[index], 0, 0, 1)
                smoke.gradient.bounds = smoke.offset.bounds
                smoke.gradient.position = smoke.rotation.position
                let scale = geometry.smokeScales[index]
                smoke.gradient.transform = CATransform3DMakeScale(scale.width, scale.height, 1)
                smoke.mask.frame = smoke.gradient.bounds
            }
        }
    }

    private func installMotionAnimations(time: TimeInterval) {
        let cloudWaves = HomeAmbientLayerGeometry.cloudWaves(size: renderedSize)
        for (index, cloud) in clouds.enumerated() {
            add(cloudWaves[index].x, to: cloud, keyPath: "position.x", time: time)
            add(cloudWaves[index].y, to: cloud, keyPath: "position.y", time: time)
        }
        let smokeWaves = HomeAmbientLayerGeometry.smokeWaves(size: renderedSize)
        for (index, smoke) in smoke.enumerated() {
            var x = smokeWaves[index].x, y = smokeWaves[index].y
            x = HomeAmbientWave(base: renderedSize.width / 2, amplitude: x.amplitude, period: x.period,
                                phase: x.phase, isCosine: x.isCosine)
            y = HomeAmbientWave(base: renderedSize.height / 2, amplitude: y.amplitude, period: y.period,
                                phase: y.phase, isCosine: y.isCosine)
            add(x, to: smoke.offset, keyPath: "position.x", time: time)
            add(y, to: smoke.offset, keyPath: "position.y", time: time)
            let rotation = smokeWaves[index].rotation
            let nativeRotation = HomeAmbientWave(base: -rotation.base, amplitude: -rotation.amplitude,
                period: rotation.period, phase: rotation.phase, isCosine: rotation.isCosine)
            add(nativeRotation, to: smoke.rotation, keyPath: "transform.rotation.z", time: time)
        }
    }

    private func add(_ wave: HomeAmbientWave, to layer: CALayer, keyPath: String, time: TimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = wave.samples(startingAt: time)
        animation.duration = wave.period
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        // Preserve the previous ambient cadence without a SwiftUI timer. This
        // is a system scheduling preference rather than an FPS guarantee.
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "ambient.\(keyPath)")
    }

    private func removeMotionAnimations() {
        for cloud in clouds { ["position.x", "position.y"].forEach { cloud.removeAnimation(forKey: "ambient.\($0)") } }
        for smoke in smoke {
            ["position.x", "position.y"].forEach { smoke.offset.removeAnimation(forKey: "ambient.\($0)") }
            smoke.rotation.removeAnimation(forKey: "ambient.transform.rotation.z")
        }
    }

    private func applyPalette(_ palette: HomeAmbientPalette, duration: TimeInterval) {
        let left = NSColor(palette.left.ambientColor).usingColorSpace(.sRGB) ?? NSColor(palette.left.ambientColor)
        let right = NSColor(palette.rightLightColor).usingColorSpace(.sRGB) ?? NSColor(palette.rightLightColor)
        withoutActions {
            for (index, cloud) in clouds.enumerated() {
                let color = index == 1 ? right : left
                let opacity: CGFloat = [0.46, 0.42, 0.16][index]
                setColors([opacity, opacity * 0.74, opacity * 0.23, 0].map { color.withAlphaComponent($0).cgColor },
                          on: cloud, duration: duration)
            }
            for (index, smoke) in smoke.enumerated() {
                let opacity: CGFloat = index == 0 ? 1.4 : 0.9
                setColors([left.withAlphaComponent(0.29 * opacity).cgColor,
                           right.withAlphaComponent(0.25 * opacity).cgColor], on: smoke.gradient, duration: duration)
            }
        }
    }

    private func setColors(_ colors: [CGColor], on gradient: CAGradientLayer, duration: TimeInterval) {
        let previous = (gradient.presentation()?.colors ?? gradient.colors)
        gradient.removeAnimation(forKey: "ambientPalette")
        gradient.colors = colors
        if duration > 0, let previous {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = previous
            animation.toValue = colors
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(animation, forKey: "ambientPalette")
        }
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private final class SmokeLayers {
        let offset = CALayer()
        let rotation = CALayer()
        let gradient = CAGradientLayer()
        let mask = CALayer()
        init() {
            offset.isGeometryFlipped = true
            rotation.isGeometryFlipped = true
            offset.isHidden = true
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            // Composite the whole transformed, masked group against the
            // canvas, rather than screening into an intermediate clear layer.
            offset.compositingFilter = HomeAmbientScreenFilter.make()
            mask.contentsGravity = .resize
            mask.minificationFilter = .trilinear
            mask.magnificationFilter = .linear
            // SwiftUI's decorative CGImage uses a top-down image orientation.
            // Geometry flipping changes positions, not CALayer.contents, so
            // orient this image explicitly without changing gradient or drift.
            mask.transform = CATransform3DMakeScale(1, -1, 1)
            gradient.mask = mask
            offset.addSublayer(rotation)
            rotation.addSublayer(gradient)
        }
    }
}

/// SwiftUI's original .screen blends encoded sRGB components. Core Image's
/// built-in screen filter works in linear light, which lifts these translucent
/// clouds substantially. Public tone-curve filters preserve the previous blend
/// while allowing Core Animation to own the changing layer geometry.
@objc(SideBHomeAmbientScreenFilter)
private final class HomeAmbientScreenFilter: CIFilter {
    private static let registeredName = "SideBHomeAmbientEncodedScreen"
    private static let registration: Void = {
        CIFilter.registerName(registeredName, constructor: Constructor(), classAttributes: [
            kCIAttributeFilterDisplayName: "Home ambient screen",
            kCIAttributeFilterCategories: [kCICategoryCompositeOperation, kCICategoryStillImage]
        ])
    }()

    @objc dynamic var inputImage: CIImage?
    @objc dynamic var inputBackgroundImage: CIImage?

    static func make() -> CIFilter {
        _ = registration
        return HomeAmbientScreenFilter()
    }

    override var inputKeys: [String] { [kCIInputImageKey, kCIInputBackgroundImageKey] }
    override var outputKeys: [String] { [kCIOutputImageKey] }
    override var attributes: [String: Any] {
        [kCIAttributeFilterDisplayName: "Home ambient screen",
         kCIAttributeFilterCategories: [kCICategoryCompositeOperation, kCICategoryStillImage],
         kCIInputImageKey: [kCIAttributeClass: "CIImage"],
         kCIInputBackgroundImageKey: [kCIAttributeClass: "CIImage"],
         kCIOutputImageKey: [kCIAttributeClass: "CIImage"]]
    }

    override func setDefaults() { inputImage = nil; inputBackgroundImage = nil }

    override var outputImage: CIImage? {
        guard let foreground = inputImage, let background = inputBackgroundImage else { return nil }
        let encodedForeground = foreground.applyingFilter("CILinearToSRGBToneCurve")
        let encodedBackground = background.applyingFilter("CILinearToSRGBToneCurve")
        return encodedForeground.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: encodedBackground])
            .applyingFilter("CISRGBToneCurveToLinear")
            .cropped(to: background.extent)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = HomeAmbientScreenFilter()
        result.inputImage = inputImage
        result.inputBackgroundImage = inputBackgroundImage
        return result
    }

    private final class Constructor: NSObject, CIFilterConstructor {
        func filter(withName name: String) -> CIFilter? {
            name == HomeAmbientScreenFilter.registeredName ? HomeAmbientScreenFilter() : nil
        }
    }
}
