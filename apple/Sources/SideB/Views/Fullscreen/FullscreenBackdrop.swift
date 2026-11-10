import SwiftUI

/// Foreground-only canvas. The persistent backdrop belongs to WindowRootView,
/// outside this conditional presentation and its slide transition.
struct FullscreenCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: PlayerViewModel
    @Binding var isSidebarExpanded: Bool
    let router: NavigationRouter?

    @State private var retainedMode: PlaybackPresentation?
    @State private var surfaceVisible = false

    init(viewModel: PlayerViewModel, isSidebarExpanded: Binding<Bool>, router: NavigationRouter?) {
        self.viewModel = viewModel
        _isSidebarExpanded = isSidebarExpanded
        self.router = router
        let mode = viewModel.playbackPresentation.mode
        _retainedMode = State(initialValue: mode == .bar ? nil : mode)
        _surfaceVisible = State(initialValue: mode == .fullscreen)
    }

    var body: some View {
        GeometryReader { proxy in
            let lateral = retainedMode == .sidebar
            let width = lateral ? PlaybackSidebarLayout.width : proxy.size.width
            let height = lateral ? max(0, proxy.size.height - PlaybackSidebarLayout.inset * 2) : proxy.size.height
            ZStack(alignment: .trailing) {
                if let retainedMode {
                    FullscreenNowPlayingView(viewModel: viewModel,
                        canvasSize: CGSize(width: width, height: height),
                        sidebarProgress: isSidebarExpanded ? 1 : 0, router: router,
                        presentationMode: retainedMode)
                        .frame(width: width, height: height)
                        .padding(.trailing, lateral ? PlaybackSidebarLayout.inset : 0)
                        .offset(x: !surfaceVisible && lateral && !reduceMotion ? 24 : 0,
                                y: !surfaceVisible && !lateral && !reduceMotion ? 24 : 0)
                        .opacity(surfaceVisible ? 1 : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .trailing)
        }
        .ignoresSafeArea(.container, edges: .top)
        .windowGestureRegion(.volumeExcluded, active: viewModel.isFullscreenPresented)
        .onHover { if !$0 { viewModel.volumeScroll.cancel() } }
        .allowsHitTesting(viewModel.isPlaybackSurfaceVisible && surfaceVisible)
        .accessibilityHidden(!viewModel.isPlaybackSurfaceVisible || !surfaceVisible)
        .task(id: viewModel.playbackPresentation.mode) {
            let requested = viewModel.playbackPresentation.mode
            if requested == .bar {
                withAnimation(.easeInOut(duration: 0.28)) { surfaceVisible = false }
                do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
                guard !Task.isCancelled, viewModel.playbackPresentation.mode == .bar else { return }
                retainedMode = nil
            } else {
                let inserting = retainedMode == nil
                retainedMode = requested
                if inserting && requested == .sidebar {
                    // Let the bottom bar leave before revealing the lateral surface.
                    do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                }
                guard !Task.isCancelled, viewModel.playbackPresentation.mode == requested else { return }
                withAnimation(.easeInOut(duration: 0.28)) { surfaceVisible = true }
            }
        }
    }
}

/// One noninteractive artwork background across the whole window, behind both
/// columns and the floating sidebar. Its viewport does not resize with the sidebar.
struct FullscreenBackdrop: View {
    let thumbnail: String?
    let trackID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.sidebDarkBackground
                if let thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 300) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 300, height: 300)) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.4)
                            .blur(radius: 75)
                            .overlay(Color.black.opacity(0.72))
                    } placeholder: {
                        Color.sidebDarkBackground
                    }
                    .id("blur_\(trackID ?? url.absoluteString)")
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.07, green: 0.07, blue: 0.08), Color.sidebDarkBackground],
                        startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pure sampled artwork palette for the right-hand playback sidebar and hero blend.
/// Preserves the cover's real hue in dark-mode legible luminance, uses a neutral
/// charcoal fallback without blue bias when no artwork or monochrome cover is present,
/// and avoids fading chromatic covers into pure black.
struct PlaybackSidebarPalette: Sendable, Equatable {
    let primary: HomeAmbientRGB
    let secondary: HomeAmbientRGB
    let isChromatic: Bool

    static let neutral = Self(
        primary: HomeAmbientRGB(red: 0.14, green: 0.14, blue: 0.14),
        secondary: HomeAmbientRGB(red: 0.09, green: 0.09, blue: 0.09),
        isChromatic: false
    )

    func tintColor(reduceTransparency: Bool = false, increasedContrast: Bool = false) -> Color {
        let factor: Double = (reduceTransparency || increasedContrast) ? 0.78 : 1.0
        return Color(
            red: primary.red * factor,
            green: primary.green * factor,
            blue: primary.blue * factor
        )
    }

    /// A continuous chromatic surface for the sidebar, with luminance capped
    /// for white controls. Fullscreen keeps its existing palette presentation.
    func surfaceColor(reduceTransparency: Bool = false, increasedContrast: Bool = false) -> Color {
        if reduceTransparency || increasedContrast {
            return tintColor(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast)
        }
        let rgb = Self.clampedForWhiteForeground(
            HomeAmbientRGB(red: primary.red * 1.18, green: primary.green * 1.18, blue: primary.blue * 1.18), maxLuminance: 0.115)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    func bottomSurfaceColor(reduceTransparency: Bool = false, increasedContrast: Bool = false) -> Color {
        if reduceTransparency || increasedContrast {
            return secondaryColor(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast)
        }
        let rgb = Self.clampedForWhiteForeground(
            HomeAmbientRGB(red: secondary.red * 1.08, green: secondary.green * 1.08, blue: secondary.blue * 1.08), maxLuminance: 0.075)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    func secondaryColor(reduceTransparency: Bool = false, increasedContrast: Bool = false) -> Color {
        let factor: Double = (reduceTransparency || increasedContrast) ? 0.75 : 1.0
        return Color(
            red: secondary.red * factor,
            green: secondary.green * factor,
            blue: secondary.blue * factor
        )
    }

    /// Pure calculation from a raw RGBA buffer and an explicit grid side (width == height).
    /// Samples top ~22% and bottom ~22% row bands for seamless boundary blending,
    /// falling back per band to the global cover calculation when a band lacks legible chroma.
    static func from(rgba: [UInt8], side: Int) -> Self {
        guard side >= 1, rgba.count == side * side * 4 else {
            return .neutral
        }
        guard side >= 2 else {
            return fromGlobal(rgba: rgba)
        }

        let bandRows = min(max(1, Int((Double(side) * 0.22).rounded())), side / 2)
        let bytesPerRow = side * 4
        let topByteCount = bandRows * bytesPerRow
        let bottomByteStart = (side - bandRows) * bytesPerRow
        let bottomByteCount = bandRows * bytesPerRow

        let topRgba = Array(rgba[0..<topByteCount])
        let bottomRgba = Array(rgba[bottomByteStart..<(bottomByteStart + bottomByteCount)])

        let topTints = HomeAmbientPaletteSampler.tints(rgba: topRgba)
        let bottomTints = HomeAmbientPaletteSampler.tints(rgba: bottomRgba)

        let topDominant = topTints.first
        let topIsChromatic = (topDominant?.chroma ?? 0) >= 0.06

        let bottomDominant = bottomTints.first
        let bottomIsChromatic = (bottomDominant?.chroma ?? 0) >= 0.06

        if topIsChromatic, bottomIsChromatic, let topDominant, let bottomDominant {
            return Self(
                primary: primaryColor(from: topDominant),
                secondary: secondaryColor(from: bottomDominant),
                isChromatic: true
            )
        }

        let globalPalette = fromGlobal(rgba: rgba)
        let primaryRGB: HomeAmbientRGB = {
            if topIsChromatic, let topDominant {
                return primaryColor(from: topDominant)
            }
            return globalPalette.primary
        }()

        let secondaryRGB: HomeAmbientRGB = {
            if bottomIsChromatic, let bottomDominant {
                return secondaryColor(from: bottomDominant)
            }
            return globalPalette.secondary
        }()

        let isChromatic = topIsChromatic || bottomIsChromatic || globalPalette.isChromatic
        return Self(primary: primaryRGB, secondary: secondaryRGB, isChromatic: isChromatic)
    }

    /// Pure calculation from a raw RGBA buffer. If square (width == height), samples top and bottom bands.
    static func from(rgba: [UInt8]) -> Self {
        let pixelCount = rgba.count / 4
        let side = Int(Double(pixelCount).squareRoot())
        if side * side == pixelCount, side >= 2 {
            return from(rgba: rgba, side: side)
        }
        return fromGlobal(rgba: rgba)
    }

    private static func fromGlobal(rgba: [UInt8]) -> Self {
        let tints = HomeAmbientPaletteSampler.tints(rgba: rgba)
        if !tints.isEmpty {
            return from(tints: tints, fallbackLuminance: nil)
        }
        guard rgba.count >= 4, rgba.count.isMultiple(of: 4) else { return .neutral }
        var totalLuminance: Double = 0
        var count = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Double(rgba[offset + 3]) / 255.0
            guard alpha > 0.5 else { continue }
            let r = Double(rgba[offset]) / 255.0
            let g = Double(rgba[offset + 1]) / 255.0
            let b = Double(rgba[offset + 2]) / 255.0
            totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
            count += 1
        }
        guard count > 0 else { return .neutral }
        return from(tints: [], fallbackLuminance: totalLuminance / Double(count))
    }

    static func from(tints: [HomeAmbientRGB], fallbackLuminance: Double? = nil) -> Self {
        guard let dominant = tints.first, dominant.chroma >= 0.06 else {
            guard let lum = fallbackLuminance else { return .neutral }
            let top = min(0.20, max(0.11, 0.11 + lum * 0.09))
            let bottom = min(0.14, max(0.08, top * 0.68))
            return Self(
                primary: HomeAmbientRGB(red: top, green: top, blue: top),
                secondary: HomeAmbientRGB(red: bottom, green: bottom, blue: bottom),
                isChromatic: false
            )
        }

        var hue = hueFraction(of: dominant)
        let maxC = max(dominant.red, dominant.green, dominant.blue)
        let rawSat = dominant.chroma / max(maxC, 0.001)

        // Warmth preservation: prevent yellow/lime (0.12 - 0.20) from becoming dull olive green
        if hue >= 0.12 && hue <= 0.20 {
            let t = (hue - 0.12) / 0.08
            hue = 0.11 + t * 0.03
        }

        let sat = min(0.50, max(0.18, 0.08 + rawSat * 0.60))

        var secondHue: Double = {
            guard tints.count > 1, tints[1].chroma >= 0.10 else { return hue }
            let candidate = hueFraction(of: tints[1])
            let delta = shortestHueDelta(from: hue, to: candidate)
            return (hue + delta * 0.25 + 1.0).truncatingRemainder(dividingBy: 1.0)
        }()

        if secondHue >= 0.12 && secondHue <= 0.20 {
            let t = (secondHue - 0.12) / 0.08
            secondHue = 0.11 + t * 0.03
        }

        let primaryRGB = clampedForWhiteForeground(hsl(hue: hue, saturation: sat, lightness: 0.24), maxLuminance: 0.11)
        let secondaryRGB = clampedForWhiteForeground(hsl(hue: secondHue, saturation: sat * 0.88, lightness: 0.15), maxLuminance: 0.065)
        return Self(primary: primaryRGB, secondary: secondaryRGB, isChromatic: true)
    }

    static func from(cgImage: CGImage) -> Self {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return from(tints: HomeAmbientPaletteSampler.tints(of: cgImage))
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return from(rgba: pixels, side: side)
    }

    @MainActor
    static func resolve(thumbnail: String?) async -> Self {
        guard let thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 48),
              let image = await ImageCache.shared.image(for: url, targetSize: CGSize(width: 48, height: 48)),
              !Task.isCancelled else { return .neutral }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return .neutral }
        return await Task.detached(priority: .utility) {
            Self.from(cgImage: cgImage)
        }.value
    }

    private static func hueFraction(of rgb: HomeAmbientRGB) -> Double {
        let maximum = max(rgb.red, rgb.green, rgb.blue)
        let chroma = rgb.chroma
        guard chroma > 0 else { return 0 }
        let raw: Double
        if maximum == rgb.red { raw = (rgb.green - rgb.blue) / chroma / 6.0 }
        else if maximum == rgb.green { raw = ((rgb.blue - rgb.red) / chroma + 2.0) / 6.0 }
        else { raw = ((rgb.red - rgb.green) / chroma + 4.0) / 6.0 }
        return (raw + 1.0).truncatingRemainder(dividingBy: 1.0)
    }

    private static func shortestHueDelta(from a: Double, to b: Double) -> Double {
        var delta = b - a
        if delta > 0.5 { delta -= 1.0 }
        if delta < -0.5 { delta += 1.0 }
        return delta
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> HomeAmbientRGB {
        let a = saturation * min(lightness, 1.0 - lightness)
        func component(_ n: Double) -> Double {
            let k = (n + hue * 12.0).truncatingRemainder(dividingBy: 12.0)
            return max(0.0, min(1.0, lightness - a * max(-1.0, min(k - 3.0, 9.0 - k, 1.0))))
        }
        return HomeAmbientRGB(red: component(0), green: component(8), blue: component(4))
    }

    private static func clampedForWhiteForeground(_ color: HomeAmbientRGB, maxLuminance: Double) -> HomeAmbientRGB {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var r = color.red, g = color.green, b = color.blue
        while 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > maxLuminance {
            r *= 0.94; g *= 0.94; b *= 0.94
        }
        return HomeAmbientRGB(red: r, green: g, blue: b)
    }

    private static func primaryColor(from dominant: HomeAmbientRGB) -> HomeAmbientRGB {
        var hue = hueFraction(of: dominant)
        let maxC = max(dominant.red, dominant.green, dominant.blue)
        let rawSat = dominant.chroma / max(maxC, 0.001)

        if hue >= 0.12 && hue <= 0.20 {
            let t = (hue - 0.12) / 0.08
            hue = 0.11 + t * 0.03
        }

        let sat = min(0.50, max(0.18, 0.08 + rawSat * 0.60))
        return clampedForWhiteForeground(hsl(hue: hue, saturation: sat, lightness: 0.24), maxLuminance: 0.11)
    }

    private static func secondaryColor(from dominant: HomeAmbientRGB) -> HomeAmbientRGB {
        var hue = hueFraction(of: dominant)
        let maxC = max(dominant.red, dominant.green, dominant.blue)
        let rawSat = dominant.chroma / max(maxC, 0.001)

        if hue >= 0.12 && hue <= 0.20 {
            let t = (hue - 0.12) / 0.08
            hue = 0.11 + t * 0.03
        }

        let sat = min(0.50, max(0.18, 0.08 + rawSat * 0.60))
        return clampedForWhiteForeground(hsl(hue: hue, saturation: sat * 0.88, lightness: 0.15), maxLuminance: 0.065)
    }
}

/// Shared tinted surface behind the playback sidebar, synchronized with the hero tint.
struct PlaybackSidebarBackground: View {
    let palette: PlaybackSidebarPalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increasedContrast = contrast == .increased
        let topColor = palette.surfaceColor(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast)
        let bottomColor = palette.bottomSurfaceColor(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast)

        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.08)

            LinearGradient(
                colors: [topColor, bottomColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
