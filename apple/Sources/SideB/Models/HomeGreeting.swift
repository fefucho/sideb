import Foundation

enum HomeGreeting {
    static func localHour(date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Int {
        calendar.component(.hour, from: date)
    }

    static func messageKey(hour: Int) -> String {
        if (6..<12).contains(hour) { return "app.home.morning" }
        if (12..<20).contains(hour) { return "app.home.afternoon" }
        return "app.home.evening"
    }
}
