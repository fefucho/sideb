import CoreGraphics
import Foundation

/// A small, account-independent opacity texture, prepared once off the UI thread.
enum HomeAmbientSmoke {
    static let preparedMask = Task.detached(priority: .utility) { makeMask() }

    static func makeMask(width: Int = 384, height: Int = 256) -> CGImage? {
        guard (2...2048).contains(width), (2...2048).contains(height) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                let v = Double(y) / Double(height - 1)
                let warpX = fractal(u * 2.4 + 11, v * 2.4 - 7)
                let warpY = fractal(u * 2.4 - 19, v * 2.4 + 13)
                let flowX = u * 4.8 + warpX * 2.8
                let flowY = v * 3.2 + warpY * 2.8
                let haze = fractal(flowX, flowY)
                let ridge = 1 - abs(2 * noise(flowX + haze * 0.7, flowY * 0.72) - 1)
                let ribbon = pow(max(0, (ridge - 0.30) / 0.70), 2.8)
                let border = smoothstep(0, 0.09, u) * (1 - smoothstep(0.91, 1, u))
                let depth = pow(1 - v, 0.65)
                let density = (haze * 0.40 + ribbon * 0.60) * (0.35 + haze * 0.65) * border * depth
                let alpha = UInt8(min(255, max(0, density * 210)))
                let offset = (y * width + x) * 4
                // Premultiplied white: the image supplies opacity, never its own artwork color.
                pixels[offset] = alpha
                pixels[offset + 1] = alpha
                pixels[offset + 2] = alpha
                pixels[offset + 3] = alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func fractal(_ x: Double, _ y: Double) -> Double {
        var sum = 0.0
        var amplitude = 0.57
        var frequency = 1.0
        for _ in 0..<4 {
            sum += noise(x * frequency, y * frequency) * amplitude
            frequency *= 2.03
            amplitude *= 0.47
        }
        return sum
    }

    private static func noise(_ x: Double, _ y: Double) -> Double {
        let ix = Int(floor(x))
        let iy = Int(floor(y))
        let fx = x - Double(ix)
        let fy = y - Double(iy)
        let sx = fx * fx * (3 - 2 * fx)
        let sy = fy * fy * (3 - 2 * fy)
        let top = mix(hash(ix, iy), hash(ix + 1, iy), sx)
        let bottom = mix(hash(ix, iy + 1), hash(ix + 1, iy + 1), sx)
        return mix(top, bottom, sy)
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var value = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
        value ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value & 0xFFFFFF) / Double(0xFFFFFF)
    }

    private static func mix(_ a: Double, _ b: Double, _ amount: Double) -> Double { a + (b - a) * amount }

    private static func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }
}
