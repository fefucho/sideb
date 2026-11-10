import SwiftUI

struct LyricsSourceOptions: View {
    let source: String
    let onSelect: (String) -> Void
    private let providers = ["auto", "lyricsplus", "boidu", "lrclib", "netease", "qq", "kugou"]
    private let labels = ["LyricsPlus", "Boidu", "LRCLIB", "Netease", "QQ Music", "Kugou"]
    var body: some View {
        Menu(L10n.text("lyrics.source.choose")) {
            ForEach(Array(providers.enumerated()), id: \.element) { index, id in
                Button { onSelect(id) } label: {
                    let title = index == 0 ? L10n.text("lyrics.source.auto") : labels[index - 1]
                    if source == id { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        }
    }
}
