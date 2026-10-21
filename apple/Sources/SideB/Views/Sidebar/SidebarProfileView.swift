import SwiftUI
import SideBCore

struct SidebarProfileView: View {
    @Bindable var accountViewModel: AccountViewModel
    let rustCore: SideBCore
    let cookieStorage: CookieStorage

    var onOpenLogin: () -> Void
    var onLogout: () -> Void

    @State private var showingAccountPopover = false
    @State private var showingErrorPopover = false
    @State private var isHovering = false

    var body: some View {
        Group {
            if accountViewModel.isLoading && accountViewModel.account == nil {
                loadingSkeleton
            } else if accountViewModel.isLoggedIn {
                if let account = accountViewModel.account {
                    loggedInProfileButton(account: account)
                } else if accountViewModel.errorMessage != nil || !accountViewModel.isLoading {
                    errorProfileButton(errorMessage: accountViewModel.errorMessage)
                } else {
                    loadingSkeleton
                }
            } else {
                guestProfileButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, SidebarMetrics.size(8))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
    }

    // MARK: - Subviews

    private var guestProfileButton: some View {
        Button {
            onOpenLogin()
        } label: {
            HStack(spacing: SidebarMetrics.size(10)) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: SidebarMetrics.size(24)))
                    .foregroundStyle(Color.white.opacity(0.75))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("account.guest_mode"))
                        .font(.system(size: SidebarMetrics.size(13), weight: .medium))
                        .foregroundStyle(Color.white)

                    Text(L10n.text("account.sign_in"))
                        .font(.system(size: SidebarMetrics.size(11)))
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: SidebarMetrics.size(14)))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    private func loggedInProfileButton(account: AccountInfoRecord) -> some View {
        Button {
            showingAccountPopover = true
        } label: {
            HStack(spacing: SidebarMetrics.size(10)) {
                // Avatar
                if let thumbnail = account.thumbnail, let url = URL(string: thumbnail) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: SidebarMetrics.size(32), height: SidebarMetrics.size(32))) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .frame(width: SidebarMetrics.size(32), height: SidebarMetrics.size(32))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: SidebarMetrics.size(32), height: SidebarMetrics.size(32))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: SidebarMetrics.size(14)))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                }

                // Name & Handle
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name ?? L10n.text("account.user"))
                        .font(.system(size: SidebarMetrics.size(13), weight: .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    if let handle = account.handle {
                        Text(handle)
                            .font(.system(size: SidebarMetrics.size(11)))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    } else if let email = account.email {
                        Text(email)
                            .font(.system(size: SidebarMetrics.size(11)))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: SidebarMetrics.size(10), weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingAccountPopover, arrowEdge: .top) {
            AccountPopoverView(account: account) {
                accountViewModel.logout(core: rustCore, storage: cookieStorage) {
                    onLogout()
                }
            }
        }
    }

    private func errorProfileButton(errorMessage: String?) -> some View {
        Button {
            showingErrorPopover = true
        } label: {
            HStack(spacing: SidebarMetrics.size(10)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: SidebarMetrics.size(18)))
                    .foregroundStyle(.orange)
                    .frame(width: SidebarMetrics.size(32), height: SidebarMetrics.size(32))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("account.profile_error"))
                        .font(.system(size: SidebarMetrics.size(13), weight: .medium))
                        .foregroundStyle(Color.white)

                    Text(L10n.text("account.click_for_options"))
                        .font(.system(size: SidebarMetrics.size(11)))
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                Spacer()

                SideBEllipsisLabel()
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingErrorPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("account.profile_failed"))
                    .font(.system(size: 13, weight: .semibold))
                if let msg = errorMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(3)
                }
                Divider()
                Button {
                    showingErrorPopover = false
                    Task {
                        await accountViewModel.fetchAccount(core: rustCore)
                    }
                } label: {
                    Label(L10n.text("account.retry_connection"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    showingErrorPopover = false
                    accountViewModel.logout(core: rustCore, storage: cookieStorage) {
                        onLogout()
                    }
                } label: {
                    Label(L10n.text("account.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(width: 220)
        }
        .contextMenu {
            Button {
                Task {
                    await accountViewModel.fetchAccount(core: rustCore)
                }
            } label: {
                Label(L10n.text("account.retry_connection"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                accountViewModel.logout(core: rustCore, storage: cookieStorage) {
                    onLogout()
                }
            } label: {
                Label(L10n.text("account.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var loadingSkeleton: some View {
        HStack(spacing: SidebarMetrics.size(10)) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: SidebarMetrics.size(32), height: SidebarMetrics.size(32))

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: SidebarMetrics.size(80), height: SidebarMetrics.size(11))

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: SidebarMetrics.size(50), height: SidebarMetrics.size(9))
            }

            Spacer()
        }
    }
}
