import Foundation
import Testing
@testable import SideB

@Test func homeGreetingCoversMidnightAndDayBoundaries() {
    let cases = [(0, "evening"), (5, "evening"), (6, "morning"), (11, "morning"),
                 (12, "afternoon"), (19, "afternoon"), (20, "evening"), (23, "evening")]
    for (hour, expected) in cases {
        #expect(HomeGreeting.messageKey(hour: hour) == "app.home.\(expected)")
    }
}

@Test func homeGreetingUsesLocalCalendarRatherThanUTC() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-10T14:30:00Z"))
    for (zone, expected) in [("America/Montevideo", "morning"), ("Europe/Madrid", "afternoon"), ("Asia/Tokyo", "evening")] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        #expect(HomeGreeting.messageKey(hour: HomeGreeting.localHour(date: instant, calendar: calendar)) == "app.home.\(expected)")
    }
}
