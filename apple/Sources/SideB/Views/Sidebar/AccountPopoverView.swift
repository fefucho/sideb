import SwiftUI
import SideBCore

struct AccountPopoverView: View {
    @Environment(\.dismiss) private var dismiss
    let account: AccountInfoRecord?
    var onLogout: () -> Void

    @State private var isHoveringSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Account Info
            HStack(spacing: 12) {
                if let thumbnail = account?.thumbnail, let url = URL(string: thumbnail) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.name ?? L10n.text("account.user"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let email = account?.email {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let handle = account?.handle {
                        Text(handle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            Divider()
                .opacity(0.2)

            // Info row: Google Account connected
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                Text(L10n.text("account.active_session"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Divider()
                .opacity(0.2)

            // Logout Button
            Button(role: .destructive) {
                dismiss()
                onLogout()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                    Text(L10n.text("account.sign_out"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(isHoveringSignOut ? Color.red : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHoveringSignOut ? Color.red.opacity(0.12) : Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringSignOut = hovering
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .compatGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
