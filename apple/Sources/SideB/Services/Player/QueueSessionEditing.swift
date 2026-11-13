import SideBCore

/// Why a session (Jam) refuses a local queue operation.
enum QueueSessionRejection: Equatable {
    case shuffleRepeat, playRow, removeCurrent, editPast
}

/// Implemented by a session that owns the queue (a Spotify Jam). While one is attached to the
/// `QueueManager`, the manager's own edit entry points hand the request over instead of changing
/// the local queue; the queue then only changes when the session mirrors a new state.
/// Rows count upcoming entries: row 0 is the one that plays next.
@MainActor
protocol QueueSessionEditing: AnyObject {
    func sessionAppend(_ tracks: [SongItemRecord])
    func sessionInsert(_ tracks: [SongItemRecord], atUpcomingRow row: Int)
    func sessionMove(fromUpcomingRow from: Int, toUpcomingRow to: Int)
    func sessionRemove(upcomingRow row: Int)
    func sessionRejected(_ reason: QueueSessionRejection)
}
