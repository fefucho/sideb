import Foundation
import Observation
import SideBCore

@MainActor
@Observable
final class ExploreViewModel {
    struct ChartSection: Identifiable {
        let code: String
        let cards: [BrowseCardRecord]
        var id: String { code }
    }
    private(set) var cards: [BrowseCardRecord] = []
    private(set) var chartSections: [ChartSection] = []
    private(set) var chartCountries: [ChartCountryRecord] = []
    private(set) var detectedCountry: String?
    private var unavailableRegionCode: String?
    private var regionDetectionFailed = false
    var regionMessage: String? {
        if regionDetectionFailed { return L10n.text("explore.region.detect_failed") }
        guard let unavailableRegionCode else { return nil }
        return L10n.text("explore.region.unsupported", args: [ExploreChartRegion.name(unavailableRegionCode)])
    }
    private(set) var isLoading = false
    private var errorDescriptor: AppMessage?
    var errorMessage: String? {
        get { errorDescriptor?.text }
        set { errorDescriptor = newValue.map(AppMessage.init(verbatim:)) }
    }
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var snapshots: [ExploreSource: [BrowseCardRecord]] = [:]
    @ObservationIgnored private var order: [ExploreSource] = []
    @ObservationIgnored private var sessionRevision: Int?
    @ObservationIgnored private var activeRoute: ExploreRoute?
    @ObservationIgnored private var detectionDate: Date?
    @ObservationIgnored private var chartSnapshots: [String: ChartsPageRecord] = [:]
    @ObservationIgnored private var chartOrder: [String] = []

    func prepareSession(_ revision: Int) {
        guard sessionRevision != revision else { return }
        sessionRevision = revision
        generation &+= 1
        snapshots.removeAll()
        order.removeAll()
        cards = []
        chartSections = []
        chartCountries = []
        chartSnapshots.removeAll()
        chartOrder.removeAll()
        detectedCountry = nil
        detectionDate = nil
        unavailableRegionCode = nil
        regionDetectionFailed = false
        activeRoute = nil
        isLoading = false
        errorMessage = nil
    }

    func load(route: ExploreRoute, core: SideBCore, force: Bool = false) async {
        generation &+= 1
        let request = generation
        errorMessage = nil
        let routeChanged = activeRoute != route
        activeRoute = route
        if routeChanged { chartSections = [] }
        if route == .charts {
            await loadCharts(country: nil, core: core, request: request, force: force)
            return
        }
        if case .chartCountry(let code) = route {
            await loadCharts(country: code, core: core, request: request, force: force)
            return
        }
        chartSections = []
        guard let source = route.source else {
            cards = []
            isLoading = false
            return
        }
        cards = snapshots[source] ?? []
        touch(source)
        if snapshots[source] != nil, !force {
            isLoading = false
            return
        }
        isLoading = true
        do {
            let result: [BrowseCardRecord]
            switch source {
            case .browse(let id): result = try await core.getBrowseGrid(browseId: id, params: nil)
            case .playlists(let query): result = try await core.searchCards(query: query, category: "playlists")
            case .charts(let code): result = try await core.getCharts(countryCode: code).items
            }
            guard request == generation, !Task.isCancelled else {
                finishCancelled(request)
                return
            }
            cards = uniqueCards(result)
            snapshots[source] = cards
            touch(source)
            while order.count > 8 { snapshots.removeValue(forKey: order.removeFirst()) }
        } catch {
            guard request == generation, !Task.isCancelled else {
                finishCancelled(request)
                return
            }
            errorDescriptor = AppMessage(key: "explore.error.load_music")
        }
        isLoading = false
    }

    private func finishCancelled(_ request: UInt64) {
        if request == generation { isLoading = false }
    }

    private func touch(_ source: ExploreSource) {
        order.removeAll { $0 == source }
        order.append(source)
    }

    private func loadCharts(country: String?, core: SideBCore, request: UInt64, force: Bool) async {
        cards = []
        isLoading = true
        unavailableRegionCode = nil
        regionDetectionFailed = false
        if country == nil, force || detectionDate.map({ Date().timeIntervalSince($0) > 600 }) ?? true {
            let detected = try? await core.detectMusicCountry()
            guard request == generation, !Task.isCancelled else { finishCancelled(request); return }
            detectedCountry = detected
            detectionDate = Date()
        }
        do {
            let code = country ?? "ZZ"
            let first = try await chartPage(code, core: core, request: request, force: force)
            guard request == generation, !Task.isCancelled else { finishCancelled(request); return }
            chartCountries = first.countries
            chartSections = [.init(code: code, cards: uniqueCards(first.items))]
            if country == nil {
                if let detectedCountry, detectedCountry != "ZZ", chartCountries.contains(where: { $0.code == detectedCountry }) {
                    let local = try await chartPage(detectedCountry, core: core, request: request, force: force)
                    guard request == generation, !Task.isCancelled else { finishCancelled(request); return }
                    chartSections.append(.init(code: detectedCountry, cards: uniqueCards(local.items)))
                } else {
                    if let detectedCountry { unavailableRegionCode = detectedCountry }
                    else { regionDetectionFailed = true }
                }
            }
        } catch {
            guard request == generation, !Task.isCancelled else { finishCancelled(request); return }
            errorDescriptor = AppMessage(key: "explore.error.load_charts")
        }
        isLoading = false
    }

    private func chartPage(_ code: String, core: SideBCore, request: UInt64, force: Bool) async throws -> ChartsPageRecord {
        let page: ChartsPageRecord
        if let cached = chartSnapshots[code], !force { page = cached }
        else { page = try await core.getCharts(countryCode: code) }
        guard request == generation, !Task.isCancelled else { throw CancellationError() }
        chartSnapshots[code] = page
        chartOrder.removeAll { $0 == code }
        chartOrder.append(code)
        while chartOrder.count > 8 { chartSnapshots.removeValue(forKey: chartOrder.removeFirst()) }
        return page
    }

    private func uniqueCards(_ items: [BrowseCardRecord]) -> [BrowseCardRecord] {
        var seen = Set<String>()
        return items.filter {
            !$0.id.isEmpty && !$0.title.isEmpty &&
            ["album", "playlist", "artist", "song", "video"].contains($0.kind) &&
            seen.insert($0.exploreIdentity).inserted
        }
    }
}
