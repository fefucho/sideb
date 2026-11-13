import Testing
@testable import SideB

@Suite struct ConnectionsJamStateTests {
    @Test func inactiveJamLeavesTransportUntouched() {
        let state = ConnectionsJamState.inactive
        #expect(state.shuffleRepeatEnabled)
        #expect(state.nextPreviousSeekEnabled)
        #expect(state.sharedControlHelp("Siguiente") == nil)
    }

    @Test func liveJamDisablesShuffleRepeatAndGatesTransportOnControl() {
        let controlled = ConnectionsJamState(isLive: true, hostName: "Ana", hostImageURL: nil, canControl: true)
        #expect(!controlled.shuffleRepeatEnabled)
        #expect(controlled.nextPreviousSeekEnabled)
        #expect(controlled.sharedControlHelp("Siguiente") != nil)
        let guest = ConnectionsJamState(isLive: true, hostName: "Ana", hostImageURL: nil, canControl: false)
        #expect(!guest.nextPreviousSeekEnabled)
        #expect(guest.sharedControlHelp("Siguiente") != controlled.sharedControlHelp("Siguiente"))
    }
}
