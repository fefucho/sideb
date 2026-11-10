import Foundation
import Testing
@testable import SideB

@Test func queueSelectionPreferenceDefaultsToAdvanceAndSurvivesReload() throws {
    let suite = "QueuePreferenceTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(QueuePreferences.selection(in: defaults) == .advance)
    #expect(defaults.object(forKey: QueuePreferences.selectionKey) == nil)
    defaults.set(QueueRecommendationSelection.playOnly.rawValue, forKey: QueuePreferences.selectionKey)
    let reloaded = try #require(UserDefaults(suiteName: suite))
    #expect(QueuePreferences.selection(in: reloaded) == .playOnly)
    defaults.set("unknown", forKey: QueuePreferences.selectionKey)
    #expect(QueuePreferences.selection(in: defaults) == .advance)
}
