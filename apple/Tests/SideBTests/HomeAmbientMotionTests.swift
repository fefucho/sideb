import Foundation
import Testing
@testable import SideB

@Test func homeAmbientClockExcludesHiddenTimeAndResumesContinuously() {
    var clock = HomeAmbientMotionClock(time: 100)
    let origin = Date(timeIntervalSinceReferenceDate: 1000)
    clock.setRunning(true, at: origin)
    #expect(clock.time(at: origin.addingTimeInterval(10)) == 110)
    clock.setRunning(false, at: origin.addingTimeInterval(10))
    #expect(clock.time(at: origin.addingTimeInterval(70)) == 110)
    clock.setRunning(true, at: origin.addingTimeInterval(70))
    #expect(clock.time(at: origin.addingTimeInterval(70)) == 110)
    #expect(clock.time(at: origin.addingTimeInterval(75)) == 115)
    clock.setRunning(false, at: origin.addingTimeInterval(75))
    #expect(clock.time(at: origin.addingTimeInterval(100)) == 115)
}

@Test func homeAmbientClockStartsPausedAndRepeatedActivityDoesNotResetPhase() {
    var clock = HomeAmbientMotionClock(time: 42)
    let origin = Date(timeIntervalSinceReferenceDate: 1000)
    #expect(clock.time(at: origin) == 42)
    clock.setRunning(false, at: origin)
    clock.setRunning(true, at: origin.addingTimeInterval(20))
    clock.setRunning(true, at: origin.addingTimeInterval(23))
    #expect(clock.time(at: origin.addingTimeInterval(25)) == 47)
    clock.setRunning(false, at: origin.addingTimeInterval(25))
    clock.setRunning(false, at: origin.addingTimeInterval(40))
    #expect(clock.time(at: origin.addingTimeInterval(100)) == 47)
}
