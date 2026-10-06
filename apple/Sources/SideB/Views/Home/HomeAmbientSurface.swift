import SwiftUI

/// Soft artwork light with a shared texture and motion only while Home is visible.
struct HomeAmbientSurface: View {
    let palette: HomeAmbientPalette
    let isObscured: Bool
    private let previewMask: CGImage?
    @State private var smokeMask: CGImage?
    @State private var motionClock = HomeAmbientMotionClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(palette: HomeAmbientPalette, smokeMask: CGImage? = nil, isObscured: Bool = false) {
        self.palette = palette
        self.previewMask = smokeMask
        self.isObscured = isObscured
    }

    private var motionPaused: Bool { isObscured || reduceMotion || scenePhase != .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: motionPaused)) { timeline in
            surface(time: motionClock.time(at: timeline.date))
        }
        .onChange(of: motionPaused, initial: true) { _, paused in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { motionClock.setRunning(!paused, at: Date()) }
        }
        .task {
            guard previewMask == nil else { return }
            let mask = await HomeAmbientSmoke.preparedMask.value
            guard !Task.isCancelled else { return }
            if reduceMotion { smokeMask = mask }
            else { withAnimation(.easeIn(duration: 0.5)) { smokeMask = mask } }
        }
    }

    private func surface(time t: Double) -> some View {
        GeometryReader { proxy in
            let extent = max(proxy.size.width, proxy.size.height)
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Color(red: 17 / 255, green: 19 / 255, blue: 24 / 255)
                cloud(palette.left.ambientColor,
                      center: drift(0.06, 0.02, t, period: 42, amount: 0.11, phase: 0),
                      radius: extent * 0.62, opacity: 0.46)
                    .blendMode(.screen)
                cloud(palette.rightLightColor,
                      center: drift(0.94, 0.18, t, period: 50, amount: 0.11, phase: 2),
                      radius: extent * 0.58, opacity: 0.42)
                    .blendMode(.screen)
                cloud(palette.left.ambientColor,
                      center: drift(0.43, 0.73, t, period: 36, amount: 0.15, phase: 4),
                      radius: extent * 0.42, opacity: 0.16)
                    .blendMode(.screen)
                if let mask = previewMask ?? smokeMask {
                    // Two overscanned layers drifting at different speeds give parallax depth.
                    smokeLayer(mask, opacity: 1.4)
                        .scaleEffect(1.5)
                        .rotationEffect(.degrees(sin(t * 2 * .pi / 70) * 3.5))
                        .offset(x: sin(t * 2 * .pi / 45) * w * 0.11,
                                y: cos(t * 2 * .pi / 56) * h * 0.06)
                    smokeLayer(mask, opacity: 0.9)
                        .scaleEffect(x: -1.75, y: 1.75)
                        .rotationEffect(.degrees(cos(t * 2 * .pi / 88) * 4.5))
                        .offset(x: cos(t * 2 * .pi / 65 + 1) * w * 0.14,
                                y: sin(t * 2 * .pi / 78 + 2) * h * 0.08)
                }
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.08), location: 0.42),
                    .init(color: .black.opacity(0.46), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    private func smokeLayer(_ mask: CGImage, opacity: Double) -> some View {
        LinearGradient(colors: [palette.left.ambientColor.opacity(0.29 * opacity),
                                palette.rightLightColor.opacity(0.25 * opacity)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .mask {
                Image(decorative: mask, scale: 1)
                    .resizable().interpolation(.high)
            }
            .blendMode(.screen)
            .transition(.opacity)
    }

    private func drift(_ x: Double, _ y: Double, _ t: Double,
                       period: Double, amount: Double, phase: Double) -> UnitPoint {
        let a = t * 2 * .pi / period + phase
        return UnitPoint(x: x + sin(a) * amount, y: y + cos(a * 0.8) * amount)
    }

    private func cloud(_ color: Color, center: UnitPoint, radius: CGFloat, opacity: Double) -> some View {
        RadialGradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.74), location: 0.32),
            .init(color: color.opacity(opacity * 0.23), location: 0.70),
            .init(color: color.opacity(0), location: 1)
        ], center: center, startRadius: 0, endRadius: radius)
    }
}

/// Paused wall time never advances the drift phase when Home becomes visible again.
struct HomeAmbientMotionClock {
    private var frozenTime: TimeInterval
    private var runningSince: Date?

    init(time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        frozenTime = time
    }

    func time(at date: Date) -> TimeInterval {
        frozenTime + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at date: Date) {
        if running {
            if runningSince == nil { runningSince = date }
        } else if runningSince != nil {
            frozenTime = time(at: date)
            runningSince = nil
        }
    }
}

struct HomeAmbientPalette: Sendable, Equatable {
    let left: HomeAmbientRGB
    let right: HomeAmbientRGB

    static let neutral = HomeAmbientPalette(
        left: HomeAmbientRGB(red: 0.18, green: 0.22, blue: 0.28),
        right: HomeAmbientRGB(red: 0.15, green: 0.18, blue: 0.23)
    )

    var rightLightColor: Color {
        // Monochrome warm covers need a quiet counter-light instead of a full sepia wash.
        if left.chroma > 0.12, right.chroma > 0.12, left.hueDistance(to: right) < 0.10 {
            return left.counterLightColor
        }
        return right.ambientColor
    }

    static func from(_ colors: [HomeAmbientRGB]) -> HomeAmbientPalette {
        let ranked = colors.enumerated().sorted {
            $0.element.chroma == $1.element.chroma
                ? $0.offset < $1.offset : $0.element.chroma > $1.element.chroma
        }.map(\.element)
        guard let first = ranked.first else { return .neutral }
        // Repeated covers/shades must not occupy both sides when another real hue exists.
        let second = ranked.dropFirst().enumerated().max {
            let lhs = first.hueDistance(to: $0.element) * $0.element.chroma
            let rhs = first.hueDistance(to: $1.element) * $1.element.chroma
            return lhs == rhs ? $0.offset > $1.offset : lhs < rhs
        }?.element ?? first
        return HomeAmbientPalette(left: first, right: second)
    }
}

struct HomeAmbientRGB: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var chroma: Double { max(red, green, blue) - min(red, green, blue) }
    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Lift dark pigments into light without changing their hue or tinting neutral artwork.
    var ambientColor: Color {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        guard chroma > 0.08 else { return color }
        let saturation = min(0.78, max(0.48, chroma / max(maximum, 0.001)))
        let low = 0.80 * (1 - saturation)
        func lift(_ component: Double) -> Double { low + (component - minimum) / chroma * (0.80 - low) }
        return Color(red: lift(red), green: lift(green), blue: lift(blue))
    }

    func hueDistance(to other: HomeAmbientRGB) -> Double {
        let distance = abs(hue - other.hue)
        return min(distance, 1 - distance)
    }

    fileprivate var counterLightColor: Color {
        Color(hue: (hue + 0.44).truncatingRemainder(dividingBy: 1), saturation: 0.42, brightness: 0.68)
    }

    private var hue: Double {
        guard chroma > 0 else { return 0 }
        let maximum = max(red, green, blue)
        let value: Double
        if maximum == red { value = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6) / 6 }
        else if maximum == green { value = ((blue - red) / chroma + 2) / 6 }
        else { value = ((red - green) / chroma + 4) / 6 }
        return value < 0 ? value + 1 : value
    }
}
