import Testing
@testable import SideB

struct SettingsModalTests {
    @Test func allCategoriesAreDefinedWithUniqueIdentifiers() {
        let categories = SettingsCategory.allCases
        #expect(categories.count == 7)

        let ids = Set(categories.map(\.id))
        #expect(ids.count == 7)
        #expect(ids.contains("general"))
        #expect(ids.contains("playback"))
        #expect(ids.contains("appearance"))
        #expect(ids.contains("visualProviders"))
        #expect(ids.contains("homeFeed"))
        #expect(ids.contains("account"))
        #expect(ids.contains("shortcuts"))
    }

    @Test func categoriesHaveNonEmptyTitlesAndIcons() {
        for category in SettingsCategory.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.subtitle.isEmpty)
            #expect(!category.icon.isEmpty)
        }
    }
}
