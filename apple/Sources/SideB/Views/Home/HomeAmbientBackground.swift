import AppKit
import CoreGraphics
import SwiftUI

/// Shared, quiet artwork tint for the Home content and sidebar layers.
/// The shell owns placement and ordering; this view always fills its viewport.
struct HomeAmbientBackground: View {
    let thumbnails: [String]
    let sessionRevision: Int
    var isObscured = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette = HomeAmbientPalette.neutral
    @State private var paletteRevision: Int?

    private var request: PaletteRequest {
        PaletteRequest(sessionRevision: sessionRevision, thumbnails: Array(thumbnails.prefix(4)))
    }

    var body: some View {
        HomeAmbientSurface(palette: paletteRevision == sessionRevision ? palette : .neutral,
                           isObscured: isObscured)
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: self.request) {
            let currentRequest = self.request
            let requestedRevision = currentRequest.sessionRevision
            let resolved = await HomeAmbientPaletteCache.shared.resolve(
                currentRequest.thumbnails,
                sessionRevision: requestedRevision
            )
            guard !Task.isCancelled,
                  self.sessionRevision == requestedRevision,
                  currentRequest == self.request
            else { return }

            if self.reduceMotion {
                self.paletteRevision = requestedRevision
                self.palette = resolved
            } else {
                withAnimation(.easeInOut(duration: 1.0)) {
                    self.paletteRevision = requestedRevision
                    self.palette = resolved
                }
            }
        }
        .onChange(of: self.sessionRevision) { _, _ in
            // Remove the previous account's artwork tint in this same update.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.paletteRevision = self.sessionRevision
                self.palette = .neutral
            }
        }
    }
}

private struct PaletteRequest: Hashable {
    let sessionRevision: Int
    let thumbnails: [String]
}

/// Small pure sampler so RGB fixtures can exercise the image policy without AppKit or a window.
enum HomeAmbientPaletteSampler {
    static func dominantTint(rgba: [UInt8]) -> HomeAmbientRGB? {
        tints(rgba: rgba).first
    }

    /// Keep a small accent as well as the dominant family instead of losing it to skin/earth tones.
    static func tints(rgba: [UInt8]) -> [HomeAmbientRGB] {
        guard rgba.count >= 4, rgba.count.isMultiple(of: 4) else { return [] }

        // Keep hue families separate: a global RGB average makes a small but real
        // artwork color disappear into large black, white, or grey regions.
        let hueBinCount = 12
        var counts = [Int](repeating: 0, count: hueBinCount)
        var redTotals = [Double](repeating: 0, count: hueBinCount)
        var greenTotals = [Double](repeating: 0, count: hueBinCount)
        var blueTotals = [Double](repeating: 0, count: hueBinCount)
        var weights = [Double](repeating: 0, count: hueBinCount)

        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Double(rgba[offset + 3]) / 255
            guard alpha > 0.5 else { continue }

            let red = Double(rgba[offset]) / 255
            let green = Double(rgba[offset + 1]) / 255
            let blue = Double(rgba[offset + 2]) / 255
            let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            guard brightness > 0.055, brightness < 0.92 else { continue }

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let chroma = maximum - minimum
            let saturation = chroma / max(maximum, 0.001)
            guard saturation >= 0.16 else { continue }

            let hue = hueFraction(red: red, green: green, blue: blue, maximum: maximum, chroma: chroma)
            let bin = min(hueBinCount - 1, Int(hue * Double(hueBinCount)))
            let weight = alpha * (0.08 + saturation * saturation)
            counts[bin] += 1
            redTotals[bin] += red * weight
            greenTotals[bin] += green * weight
            blueTotals[bin] += blue * weight
            weights[bin] += weight
        }

        let minimumSupport = max(3, (rgba.count / 4) / 128)
        let ranked = counts.indices.filter { counts[$0] >= minimumSupport && weights[$0] > 0 }
            .sorted {
                let lhs = weights[$0] / Double(counts[$0]).squareRoot()
                let rhs = weights[$1] / Double(counts[$1]).squareRoot()
                return lhs == rhs ? $0 < $1 : lhs > rhs
            }
        return ranked.prefix(3).map { bin in
            let red = redTotals[bin] / weights[bin]
            let green = greenTotals[bin] / weights[bin]
            let blue = blueTotals[bin] / weights[bin]
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let chromaScale = 0.84
            return HomeAmbientRGB(
                red: luminance + (red - luminance) * chromaScale,
                green: luminance + (green - luminance) * chromaScale,
                blue: luminance + (blue - luminance) * chromaScale
            )
        }
    }

    private static func hueFraction(red: Double, green: Double, blue: Double,
                                    maximum: Double, chroma: Double) -> Double {
        let hue: Double
        if maximum == red {
            hue = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            hue = ((blue - red) / chroma + 2) / 6
        } else {
            hue = ((red - green) / chroma + 4) / 6
        }
        return hue < 0 ? hue + 1 : hue
    }
}

private actor HomeAmbientPaletteCache {
    static let shared = HomeAmbientPaletteCache()

    private struct Entry {
        let tints: [HomeAmbientRGB]
        var lastAccess: UInt64
    }

    private let capacity = 64
    private var sessionRevision: Int?
    private var clock: UInt64 = 0
    private var entries: [String: Entry] = [:]

    func resolve(_ thumbnails: [String], sessionRevision requestedRevision: Int) async -> HomeAmbientPalette {
        adoptSession(requestedRevision)
        guard sessionRevision == requestedRevision else { return .neutral }
        var colors: [HomeAmbientRGB] = []

        for source in thumbnails.prefix(4) {
            guard !Task.isCancelled,
                  sessionRevision == requestedRevision,
                  let url = ImageURLHelper.optimizedThumbnailURL(from: source, targetPixelSize: 32)
            else { continue }

            let key = source
            if var cached = entries[key] {
                clock &+= 1
                cached.lastAccess = clock
                entries[key] = cached
                colors.append(contentsOf: cached.tints)
                continue
            }

            guard let image = await ImageCache.shared.image(for: url, targetSize: CGSize(width: 32, height: 32)),
                  !Task.isCancelled,
                  sessionRevision == requestedRevision,
                  let cgImage = Self.cgImage(from: image)
            else { continue }

            let sampled = await Task.detached(priority: .utility) {
                HomeAmbientPaletteSampler.tints(of: cgImage)
            }.value
            guard !sampled.isEmpty, !Task.isCancelled, sessionRevision == requestedRevision else { continue }

            // Actor reentrancy allows a session reset while ImageCache is loading.
            guard sessionRevision == requestedRevision else { continue }
            clock &+= 1
            entries[key] = Entry(tints: sampled, lastAccess: clock)
            if entries.count > capacity,
               let leastRecent = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                entries.removeValue(forKey: leastRecent)
            }
            colors.append(contentsOf: sampled)
        }

        guard sessionRevision == requestedRevision else { return .neutral }
        return HomeAmbientPalette.from(colors)
    }

    private func adoptSession(_ revision: Int) {
        if let sessionRevision, revision < sessionRevision { return }
        guard sessionRevision != revision else { return }
        sessionRevision = revision
        entries.removeAll(keepingCapacity: true)
        clock = 0
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}

extension HomeAmbientPaletteSampler {
    static func tints(of cgImage: CGImage) -> [HomeAmbientRGB] {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return [] }
        return HomeAmbientPaletteSampler.tints(rgba: pixels)
    }
}
