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
    private(set) var regionMessage: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
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
        regionMessage = nil
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
            errorMessage = "No se pudo cargar la música. Revisá la conexión y volvé a intentar."
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
        regionMessage = nil
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
                    regionMessage = detectedCountry.map { "YouTube no ofrece rankings de \(ExploreChartRegion.name($0)). Podés elegir otro país." }
                        ?? "No se pudo detectar tu región. Podés elegir un país en el selector."
                }
            }
        } catch {
            guard request == generation, !Task.isCancelled else { finishCancelled(request); return }
            errorMessage = "No se pudieron cargar todos los rankings. Volvé a intentar."
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
