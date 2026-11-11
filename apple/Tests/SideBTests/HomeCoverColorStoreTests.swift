import CoreGraphics
import Foundation
import Testing
@testable import SideB

private func solidPixels(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 1024) -> [UInt8] {
    (0..<count).flatMap { _ in [r, g, b, 255] }
}

private func makeImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
    var data = [UInt8]()
    for _ in 0..<(width * height) { data += [r, g, b, 255] }
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private func countingProvider(_ counter: Counter, r: UInt8 = 220, g: UInt8 = 40, b: UInt8 = 35,
                              gate: Gate? = nil) -> @Sendable () async -> CGImage? {
    { await counter.increment(); await gate?.wait(); return makeImage(width: 48, height: 20, r: r, g: g, b: b) }
}

private func waitUntil(_ counter: Counter, reaches n: Int) async {
    while await counter.value < n { await Task.yield() }
}

// MARK: Función pura

@Test func coverColorSaturatedImageGivesSameFamily() throws {
    let tint = try #require(HomeCoverColorStore.dominantColor(rgba: solidPixels(220, 40, 35)))
    #expect(tint.red > tint.green && tint.red > tint.blue)
}

@Test func coverColorNeutralsGiveNil() {
    #expect(HomeCoverColorStore.dominantColor(rgba: solidPixels(128, 128, 128)) == nil)
    #expect(HomeCoverColorStore.dominantColor(rgba: solidPixels(0, 0, 0)) == nil)
    #expect(HomeCoverColorStore.dominantColor(rgba: solidPixels(255, 255, 255)) == nil)
    #expect(HomeCoverColorStore.dominantColor(rgba: []) == nil)
}

@Test func coverColorMostChromaticWinsOverMutedMajority() throws {
    // Regla de coverColor.ts: máximo chroma entre la paleta, no el más abundante.
    let pixels = solidPixels(180, 150, 130, count: 600) + solidPixels(20, 80, 230, count: 60)
    let tint = try #require(HomeCoverColorStore.dominantColor(rgba: pixels))
    #expect(tint.blue > tint.red)
}

@Test func coverColorSamplesNon32SquareImage() throws {
    let tint = try #require(HomeCoverColorStore.sample(image: makeImage(width: 100, height: 57, r: 30, g: 60, b: 220)))
    #expect(tint.blue > tint.red && tint.blue > tint.green)
    #expect(HomeCoverColorStore.sample(image: makeImage(width: 7, height: 90, r: 128, g: 128, b: 128)) == nil)
}

// MARK: Caché

@Test @MainActor func coverColorSecondQueryUsesCache() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    let first = await store.color(url: "u", session: "s", image: countingProvider(calls))
    let second = await store.color(url: "u", session: "s", image: countingProvider(calls))
    #expect(first != nil && first == second)
    #expect(await calls.value == 1)
    #expect(store.cached(url: "u", session: "s") == .some(first))
    #expect(store.cached(url: "other", session: "s") == nil)
}

@Test @MainActor func coverColorConcurrentQueriesShareOneLoad() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    let gate = Gate()
    let a = Task { @MainActor in await store.color(url: "u", session: "s", image: countingProvider(calls, gate: gate)) }
    await waitUntil(calls, reaches: 1)
    let b = Task { @MainActor in await store.color(url: "u", session: "s", image: countingProvider(calls, gate: gate)) }
    await Task.yield()
    await gate.release()
    let (ra, rb) = (await a.value, await b.value)
    #expect(ra != nil && ra == rb)
    #expect(await calls.value == 1)
}

@Test @MainActor func coverColorFailureIsRemembered() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    let failing: @Sendable () async -> CGImage? = { await calls.increment(); return nil }
    #expect(await store.color(url: "u", session: "s", image: failing) == nil)
    #expect(await store.color(url: "u", session: "s", image: failing) == nil)
    #expect(await calls.value == 1)
    let remembered = store.cached(url: "u", session: "s")
    #expect(remembered != nil)          // calculado...
    #expect(remembered! == nil)         // ...sin color
}

@Test @MainActor func coverColorNilURLReturnsNilWithoutProvider() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    #expect(await store.color(url: nil, session: "s", image: countingProvider(calls)) == nil)
    #expect(await calls.value == 0)
}

@Test @MainActor func coverColorSessionChangeClearsCache() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    _ = await store.color(url: "u", session: "A", image: countingProvider(calls))
    #expect(store.cached(url: "u", session: "B") == nil)
    _ = await store.color(url: "u", session: "B", image: countingProvider(calls))
    #expect(await calls.value == 2)
}

@Test @MainActor func coverColorResultFinishingAfterSessionChangeIsNotStored() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    let gate = Gate()
    let late = Task { @MainActor in
        await store.color(url: "u", session: "A", image: countingProvider(calls, r: 220, g: 40, b: 35, gate: gate))
    }
    await waitUntil(calls, reaches: 1)
    let fresh = await store.color(url: "u", session: "B", image: countingProvider(calls, r: 30, g: 60, b: 220))
    await gate.release()
    _ = await late.value
    #expect(fresh != nil)
    #expect(store.cached(url: "u", session: "B") == .some(fresh))
    #expect(fresh!.blue > fresh!.red)
}

@Test @MainActor func coverColorCapacityEvictsLeastRecentlyUsed() async {
    let store = HomeCoverColorStore()
    let calls = Counter()
    for i in 0..<HomeCoverColorStore.capacity {
        _ = await store.color(url: "u\(i)", session: "s", image: countingProvider(calls))
    }
    _ = store.cached(url: "u0", session: "s")   // u0 pasa a ser la más reciente
    _ = await store.color(url: "extra", session: "s", image: countingProvider(calls))
    #expect(store.cached(url: "u1", session: "s") == nil)
    #expect(store.cached(url: "u0", session: "s") != nil)
    #expect(store.cached(url: "extra", session: "s") != nil)
}

@Test @MainActor func coverColorResetClearsEverything() async {
    let store = HomeCoverColorStore()
    _ = await store.color(url: "u", session: "s", image: countingProvider(Counter()))
    store.reset()
    #expect(store.cached(url: "u", session: "s") == nil)
}

// MARK: Mezcla del degradado

@Test func coverScrimMixesThirtyPercentCoverOverBase() {
    let mixed = HomeCoverScrim.color(cover: HomeAmbientRGB(red: 1, green: 0.5, blue: 0))
    #expect(abs(mixed.red - (0.3 + 0.7 * 11 / 255)) < 1e-12)
    #expect(abs(mixed.green - (0.15 + 0.7 * 11 / 255)) < 1e-12)
    #expect(abs(mixed.blue - (0.7 * 15 / 255)) < 1e-12)
}

@Test func coverScrimFallsBackToDarkCover() {
    let mixed = HomeCoverScrim.color(cover: nil)
    #expect(abs(mixed.red - (0.3 * 16 + 0.7 * 11) / 255) < 1e-12)
    #expect(abs(mixed.green - (0.3 * 16 + 0.7 * 11) / 255) < 1e-12)
    #expect(abs(mixed.blue - (0.3 * 20 + 0.7 * 15) / 255) < 1e-12)
}

@Test func coverScrimStops() {
    let expected: [(Double, Double)] = [(0, 0.94), (0.2, 0.80), (0.42, 0.48), (0.66, 0.14), (1, 0)]
    #expect(HomeCoverScrim.stops.count == 5)
    for (stop, want) in zip(HomeCoverScrim.stops, expected) {
        #expect(stop.location == want.0 && stop.alpha == want.1)
    }
}
