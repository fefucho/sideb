import SwiftUI
@testable import SideB

/// Static reference of the pre-native renderer for deterministic image comparisons.
/// No clock, tasks or environment observation run in this test-only view.
struct HomeAmbientReferenceSurface: View {
    let palette: HomeAmbientPalette
    let smokeMask: CGImage?
    let time: Double

    var body: some View { surface(time: time) }

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
                if let mask = smokeMask {
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
