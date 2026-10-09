import SwiftUI

/// Placeholder para carátulas o avatares de colecciones y álbumes cuando aún no cargan o fallan.
struct DetailArtworkPlaceholder: View {
    var size: CGFloat = 180
    var cornerRadius: CGFloat = AppTheme.artworkHeroRadius
    var iconSize: CGFloat = 48
    var systemImageName: String = "music.note"

    var body: some View {
        ZStack {
            Color.sidebCardBackground
            Image(systemName: systemImageName)
                .font(.system(size: iconSize))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

/// Skeleton de carga para las cabeceras fijas de 180pt en vistas de detalle (Álbum, Playlist).
struct DetailLoadingHeaderView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            RoundedRectangle(cornerRadius: AppTheme.artworkHeroRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 80, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 240, height: 28)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 140, height: 16)

                Spacer()
            }
            .frame(height: 180)
        }
    }
}

/// Estado de error estándar para vistas de detalle con mensaje y botón de reintento.
struct DetailErrorStateView: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.text("common.retry")) {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 60)
    }
}
