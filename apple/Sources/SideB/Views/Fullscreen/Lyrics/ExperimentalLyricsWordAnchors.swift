import Foundation

/// Physical neighbours bound a word's expansion independently of reading direction.
/// Sorting plus a prefix maximum also catches nested/overlapping anchors; checking
/// only the previous rectangle would miss an earlier, wider overlapping word.
enum ExperimentalLyricsWordAnchors {
    static func maximumScales(anchors: [Int: CGRect]) -> [Int: CGFloat] {
        let ordered = anchors.sorted {
            $0.value.minX == $1.value.minX ? $0.key < $1.key : $0.value.minX < $1.value.minX
        }
        var leftMaximum = -CGFloat.infinity
        var result: [Int: CGFloat] = [:]
        result.reserveCapacity(ordered.count)
        for (index, entry) in ordered.enumerated() {
            let anchor = entry.value
            var room: CGFloat = 24
            if index > 0 {
                room = min(room, max(0, anchor.minX - leftMaximum) * 0.45)
            }
            if index + 1 < ordered.count {
                room = min(room, max(0, ordered[index + 1].value.minX - anchor.maxX) * 0.45)
            }
            result[entry.key] = 1 + room / max(1, anchor.width * 0.5)
            leftMaximum = max(leftMaximum, anchor.maxX)
        }
        return result
    }
}
