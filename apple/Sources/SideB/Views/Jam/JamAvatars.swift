import SwiftUI

/// Round participant photo with an initial on a stable colour while there is no image.
struct JamAvatarView: View {
    let name: String?
    let imageURL: URL?
    var size: CGFloat = 28

    private var initial: String {
        name?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    /// The same name always gets the same colour.
    private var tint: Color {
        let seed = (name ?? "").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        return Color(hue: Double(seed) / 360, saturation: 0.42, brightness: 0.58)
    }

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Text(verbatim: initial)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
            if let imageURL {
                CachedAsyncImage(url: imageURL, targetSize: CGSize(width: size * 2, height: size * 2)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Overlapping avatars, host first. `ring` cuts each circle out of the one behind it.
struct JamAvatarStack: View {
    let members: [JamPanelMember]
    var size: CGFloat = 22
    var limit = 4
    var ring: Color = .black.opacity(0.35)

    private var ordered: [JamPanelMember] {
        members.sorted { ($0.isHost ? 0 : $0.isMe ? 1 : 2) < ($1.isHost ? 0 : $1.isMe ? 1 : 2) }
    }

    var body: some View {
        let shown = Array(ordered.prefix(limit))
        let extra = members.count - shown.count
        HStack(spacing: -size * 0.26) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, member in
                JamAvatarView(name: member.name, imageURL: member.imageURL, size: size)
                    .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
                    .zIndex(Double(shown.count - index))
            }
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.gray.opacity(0.6)))
                    .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
                    .zIndex(0)
            }
        }
        .accessibilityHidden(true)
    }
}
