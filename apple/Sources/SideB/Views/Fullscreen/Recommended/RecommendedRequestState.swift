import Foundation

/// An identical pending load is shared by the tab, toggle and mounted panel.
/// A force refresh or cancellation invalidates every earlier completion, including A→B→A.
struct RecommendedRequestState {
    struct Key: Equatable {
        let videoID: String
        let artistID: String?
        let albumID: String?
        let account: UUID
    }
    private(set) var key: Key?
    private(set) var token: UUID?
    mutating func begin(_ key: Key, force: Bool) -> UUID? {
        if !force, self.key == key, token != nil { return nil }
        let token = UUID()
        self.key = key
        self.token = token
        return token
    }
    func owns(_ token: UUID) -> Bool { self.token == token }
    mutating func finish(_ token: UUID) -> Bool {
        guard owns(token) else { return false }
        cancel()
        return true
    }
    mutating func cancel() { key = nil; token = nil }
}
