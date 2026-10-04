import SwiftUI
import SideBCore

/// Each artist retains its own destination; punctuation is never clickable.
struct TrackArtistLinks: View {
    let track: SongItemRecord
    let font: Font
    let color: Color
    let hoverColor: Color
    let onNavigate: (String?, String) -> Void
    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(track.displayArtistRuns.enumerated()), id: \.offset) { index, run in
                if let id = run.id, !id.isEmpty {
                    artistButton(run.text, id: id, index: index)
                } else if track.artistRuns.isEmpty {
                    artistButton(run.text, id: nil, index: index)
                } else {
                    Text(run.text).foregroundStyle(color)
                }
            }
        }
        .font(font)
        .lineLimit(1)
    }

    private func artistButton(_ name: String, id: String?, index: Int) -> some View {
        Button { onNavigate(id, name) } label: {
            Text(name).foregroundStyle(hoveredIndex == index ? hoverColor : color)
        }
        .buttonStyle(.plain)
        .onHover { hoveredIndex = $0 ? index : nil }
        .help("Ver artista: \(name)")
    }
}

extension SongItemRecord {
    var displayArtistRuns: [HomeArtistRunRecord] {
        guard !artistRuns.isEmpty else {
            return [HomeArtistRunRecord(text: displayArtist, id: artistId)]
        }
        let linked = artistRuns.filter { $0.id?.isEmpty == false }
        // Use an explicit separator for a pair, while retaining unlinked artist names.
        let separatorsOnly = artistRuns.filter { $0.id?.isEmpty != false }.allSatisfy {
            $0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "&,"))).isEmpty
        }
        if linked.count == 2 && separatorsOnly {
            return [
                HomeArtistRunRecord(text: linked[0].text.trimmingCharacters(in: .whitespacesAndNewlines), id: linked[0].id),
                HomeArtistRunRecord(text: " & ", id: nil),
                HomeArtistRunRecord(text: linked[1].text.trimmingCharacters(in: .whitespacesAndNewlines), id: linked[1].id)
            ]
        }
        return artistRuns
    }
}
