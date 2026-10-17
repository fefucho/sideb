import AppKit
import CoreImage
import Metal
import QuartzCore
import SwiftUI
import XCTest
@testable import SideB

/// CARenderer exercises the compositor: CALayer.render(in:) does not reliably
/// capture screen filters and masks. The sentinel below verifies both first.
@MainActor final class HomeAmbientRenderingTests: XCTestCase {
    func testNativeCompositorAndStaticReference() async throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal unavailable; visual comparison requires a compositor")
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let sentinel = CALayer()
        sentinel.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        sentinel.backgroundColor = NSColor(srgbRed: 0.3, green: 0.12, blue: 0.04, alpha: 1).cgColor
        let front = CALayer()
        front.frame = sentinel.bounds
        front.backgroundColor = NSColor(srgbRed: 0.05, green: 0.65, blue: 0.55, alpha: 1).cgColor
        front.compositingFilter = CIFilter(name: "CIScreenBlendMode")
        let mask = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(sentinel.bounds)
        path.addRect(CGRect(x: 12, y: 12, width: 8, height: 8))
        mask.path = path
        mask.fillRule = .evenOdd
        front.mask = mask
        sentinel.addSublayer(front)
        let control = try render(sentinel, size: CGSize(width: 32, height: 32), device: device, queue: queue, space: space)
        let controlBytes = rgba(control)
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            (0..<3).map { Int(controlBytes[(y * 32 + x) * 4 + $0]) }
        }
        XCTAssertEqual(rgb(16, 16), [77, 31, 10], "Mask hole must reveal the background")
        for (actual, expected) in zip(rgb(4, 4), [79, 168, 141]) {
            XCTAssertLessThanOrEqual(abs(actual - expected), 3, "Screen must be composited in linear sRGB")
        }

        let preparedSmoke = await HomeAmbientSmoke.preparedMask.value
        let smoke = try XCTUnwrap(preparedSmoke)
        let palette = HomeAmbientPalette(left: .init(red: 0.7, green: 0.2, blue: 0.08),
                                         right: .init(red: 0.06, green: 0.4, blue: 0.6))
        let output = ProcessInfo.processInfo.environment["SIDEB_AMBIENT_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let fullMatrix = ProcessInfo.processInfo.environment["SIDEB_AMBIENT_FULL_MATRIX"] == "1"
        let sizes: [(CGSize, CGFloat)] = fullMatrix ? [(CGSize(width: 960, height: 640), 1), (CGSize(width: 1321, height: 831), 1), (CGSize(width: 1512, height: 949), 1), (CGSize(width: 960, height: 640), 2)] : [(CGSize(width: 960, height: 640), 1), (CGSize(width: 960, height: 640), 2)]
        let times: [Double] = fullMatrix ? [0, 0.5, 17, 36, 42, 88, 1234.5, 800_000_000.25] : [0, 17]
        let masks: [(String, CGImage?)] = [("smoke", smoke), ("clouds", nil)]
        for (size, scale) in sizes {
            for (index, time) in times.enumerated() {
                for (maskName, mask) in masks {
                    try autoreleasepool {
                        let view = HomeAmbientLayerNSView(initialTime: time, fixedTime: time)
                        view.configure(palette: palette, smokeMask: mask, active: false, reduceMotion: true, displayScale: scale)
                        view.frame.size = size
                        view.needsLayout = true
                        view.layoutSubtreeIfNeeded()
                        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
                        let native = try render(view.renderLayer, size: pixels, device: device, queue: queue, space: space)
                        let referenceRenderer = ImageRenderer(content: HomeAmbientReferenceSurface(palette: palette, smokeMask: mask, time: time)
                            .frame(width: size.width, height: size.height))
                        referenceRenderer.scale = scale
                        referenceRenderer.colorMode = .nonLinear
                        let reference = try XCTUnwrap(referenceRenderer.cgImage)
                        XCTAssertEqual(native.width, reference.width)
                        XCTAssertEqual(native.height, reference.height)
                        let left = rgba(native), right = rgba(reference)
                        var totalError = 0, maximumError = 0
                        for offset in stride(from: 0, to: left.count, by: 4) {
                            for channel in 0..<3 {
                                let error = abs(Int(left[offset + channel]) - Int(right[offset + channel]))
                                totalError += error
                                maximumError = max(maximumError, error)
                            }
                        }
                        let mean = Double(totalError) / Double(imagePixelCount(native) * 3)
                        print("Ambient comparison \(maskName) \(Int(size.width))x\(Int(size.height)) @\(scale)x t=\(time): mean=\(mean), max=\(maximumError)")
                        // Calibrated against48 compositor/reference pairs spanning
                        // three sizes and eight phases. Detect color/flip regressions.
                        XCTAssertLessThan(mean, mask == nil ? 0.6 : 1.5)
                        XCTAssertLessThanOrEqual(maximumError, mask == nil ? 6 : 10)
                        XCTAssertTrue(stride(from: 3, to: left.count, by: 4).allSatisfy { left[$0] == 255 })
                        if let output {
                            for (label, image) in [("native", native), ("reference", reference)] {
                                let bytes = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                                try bytes.write(to: output.appendingPathComponent("\(Int(size.width))-\(Int(scale))x-\(index)-\(maskName)-\(label).png"))
                            }
                        }
                        view.releaseContent()
                    }
                }
            }
        }
    }

    private func imagePixelCount(_ image: CGImage) -> Int { image.width * image.height }

    private func render(_ root: CALayer, size: CGSize, device: any MTLDevice,
                        queue: any MTLCommandQueue, space: CGColorSpace) throws -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue, kCARendererColorSpace: space])
        renderer.layer = root
        renderer.bounds = CGRect(origin: .zero, size: size)
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let completion = try XCTUnwrap(queue.makeCommandBuffer())
        completion.commit()
        completion.waitUntilCompleted()
        if let error = completion.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(buffer.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: .byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress!, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
