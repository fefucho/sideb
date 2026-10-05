import AppKit
import CoreGraphics
import SwiftUI

struct CollectionAmbientActivity {
    let reduceMotion: Bool
    let isActive: Bool
}

private struct CollectionAmbientActivityKey: EnvironmentKey {
    static let defaultValue: CollectionAmbientActivity? = nil
}

extension EnvironmentValues {
    var collectionAmbientActivity: CollectionAmbientActivity? {
        get { self[CollectionAmbientActivityKey.self] }
        set { self[CollectionAmbientActivityKey.self] = newValue }
    }
}

/// Subtle, transparent artwork ambience for album and playlist headers.
struct CollectionAmbientBackground: View {
    let thumbnail: String?
    let identity: String
    var isInViewport = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.collectionAmbientActivity) private var activity
    @State private var palette: HomeAmbientPalette = .neutral
    @State private var paletteRequest: CollectionAmbientRequest?
    @State private var isVisible = false
    @State private var smokeMask: CGImage?

    private var request: CollectionAmbientRequest {
        CollectionAmbientRequest(thumbnail: thumbnail, identity: identity)
    }

    private var effectiveReduceMotion: Bool { activity?.reduceMotion ?? reduceMotion }
    private var motionPaused: Bool {
        effectiveReduceMotion || !(activity?.isActive ?? (scenePhase == .active)) || !isVisible || !isInViewport
    }

    var body: some View {
        let currentRequest = request
        let currentPalette = paletteRequest == currentRequest ? palette : HomeAmbientPalette.neutral

        TimelineView(.animation(minimumInterval: 1.0 / 20.0,
                                paused: motionPaused)) { timeline in
            let time = motionPaused
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
            surface(palette: currentPalette, time: time)
        }
        .task(id: request) {
            let requested = request
            let resolved = await CollectionAmbientPaletteCache.shared.resolve(thumbnail: requested.thumbnail)
            guard !Task.isCancelled, requested == request else { return }

            if effectiveReduceMotion {
                paletteRequest = requested
                palette = resolved
            } else {
                withAnimation(.easeInOut(duration: 0.8)) {
                    paletteRequest = requested
                    palette = resolved
                }
            }
        }
        .task {
            let mask = await HomeAmbientSmoke.preparedMask.value
            guard !Task.isCancelled else { return }
            smokeMask = mask
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func surface(palette: HomeAmbientPalette, time: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let radius = max(width, height) * 0.66
            ZStack {
                radial(palette.left.ambientColor,
                       x: CollectionAmbientMotion.drift(0.08, time: time, period: 132, phase: 0),
                       y: CollectionAmbientMotion.drift(0.12, time: time, period: 158, phase: 1),
                       radius: radius, opacity: 0.58)
                radial(palette.right.ambientColor,
                       x: CollectionAmbientMotion.drift(0.92, time: time, period: 174, phase: 2),
                       y: CollectionAmbientMotion.drift(0.22, time: time, period: 116, phase: 3),
                       radius: radius * 0.92, opacity: 0.50)

                if let mask = smokeMask {
                    smokeLayer(mask, palette: palette, opacity: 0.25)
                        .scaleEffect(1.12)
                        .rotationEffect(.degrees(sin(time * 2 * .pi / 170) * 0.8))
                        .offset(x: sin(time * 2 * .pi / 138) * width * 0.025,
                                y: cos(time * 2 * .pi / 164) * height * 0.018)
                    smokeLayer(mask, palette: palette, opacity: 0.20)
                        .scaleEffect(x: -1.18, y: 1.18)
                        .rotationEffect(.degrees(cos(time * 2 * .pi / 180) * 0.7))
                        .offset(x: cos(time * 2 * .pi / 152 + 1) * width * 0.03,
                                y: sin(time * 2 * .pi / 172 + 2) * height * 0.02)
                }
            }
            .frame(width: width, height: height)
            .mask {
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(CollectionAmbientMotion.fadeOpacity(at: 0.60)), location: 0.60),
                    .init(color: .white.opacity(CollectionAmbientMotion.fadeOpacity(at: 0.70)), location: 0.70),
                    .init(color: .white.opacity(CollectionAmbientMotion.fadeOpacity(at: 0.80)), location: 0.80),
                    .init(color: .white.opacity(CollectionAmbientMotion.fadeOpacity(at: 0.90)), location: 0.90),
                    .init(color: .white.opacity(CollectionAmbientMotion.fadeOpacity(at: 1)), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
    }

    private func radial(_ color: Color, x: Double, y: Double,
                        radius: CGFloat, opacity: Double) -> some View {
        RadialGradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.55), location: 0.4),
            .init(color: color.opacity(opacity * 0.18), location: 0.72),
            .init(color: .clear, location: 1)
        ], center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: radius)
        .blendMode(.screen)
    }

    private func smokeLayer(_ mask: CGImage, palette: HomeAmbientPalette,
                            opacity: Double) -> some View {
        LinearGradient(colors: [palette.left.ambientColor.opacity(opacity),
                                palette.right.ambientColor.opacity(opacity)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .mask {
                Image(decorative: mask, scale: 1)
                    .resizable().interpolation(.high)
            }
            .blendMode(.screen)
    }
}

struct CollectionAmbientMotion {
    static func drift(_ origin: Double, time: Double, period: Double, phase: Double = 0) -> Double {
        origin + sin(time * 2 * .pi / period + phase) * 0.027
    }

    static func fadeOpacity(at normalizedY: Double) -> Double {
        let start = 0.60
        let progress = min(1, max(0, (normalizedY - start) / (1 - start)))
        let eased = progress * progress * (3 - 2 * progress)
        return 1 - eased
    }
}

private struct CollectionAmbientRequest: Hashable {
    let thumbnail: String?
    let identity: String
}

private actor CollectionAmbientPaletteCache {
    static let shared = CollectionAmbientPaletteCache()

    private struct Entry {
        let tints: [HomeAmbientRGB]
        var lastAccess: UInt64
    }

    private let capacity = 32
    private var clock: UInt64 = 0
    private var entries: [String: Entry] = [:]

    func resolve(thumbnail: String?) async -> HomeAmbientPalette {
        guard let thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 32)
        else { return .neutral }

        if var cached = entries[thumbnail] {
            clock &+= 1
            cached.lastAccess = clock
            entries[thumbnail] = cached
            return HomeAmbientPalette.from(cached.tints)
        }

        guard let image = await ImageCache.shared.image(for: url, targetSize: CGSize(width: 32, height: 32)),
              !Task.isCancelled,
              let cgImage = Self.cgImage(from: image)
        else { return .neutral }

        let tints = await Task.detached(priority: .utility) {
            HomeAmbientPaletteSampler.tints(of: cgImage)
        }.value
        guard !Task.isCancelled, !tints.isEmpty else { return .neutral }

        clock &+= 1
        entries[thumbnail] = Entry(tints: tints, lastAccess: clock)
        if entries.count > capacity,
           let leastRecent = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            entries.removeValue(forKey: leastRecent)
        }
        return HomeAmbientPalette.from(tints)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
