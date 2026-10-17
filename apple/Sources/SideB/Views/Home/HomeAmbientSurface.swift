import SwiftUI

/// Palette and mask lifecycle remain in SwiftUI; Core Animation owns visible motion.
struct HomeAmbientSurface: View {
    let palette: HomeAmbientPalette
    let isObscured: Bool
    private let previewMask: CGImage?
    @State private var smokeMask: CGImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(palette: HomeAmbientPalette, smokeMask: CGImage? = nil, isObscured: Bool = false) {
        self.palette = palette
        self.previewMask = smokeMask
        self.isObscured = isObscured
    }

    var body: some View {
        HomeAmbientLayerView(palette: palette, smokeMask: previewMask ?? smokeMask,
                             isObscured: isObscured, reduceMotion: reduceMotion, scenePhase: scenePhase)
        .task {
            guard previewMask == nil else { return }
            let mask = await HomeAmbientSmoke.preparedMask.value
            guard !Task.isCancelled else { return }
            if reduceMotion { smokeMask = mask }
            else { withAnimation(.easeIn(duration: 0.5)) { smokeMask = mask } }
        }
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
