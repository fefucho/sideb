import AppKit
import SwiftUI

extension FullscreenNowPlayingView {
    var sidebarScene: some View {
        GeometryReader { proxy in
            let headerHeight: CGFloat = 58
            let upperHeight = max(0, proxy.size.height - PlaybackSidebarLayout.footerHeight(for: proxy.size.height, panel: viewModel.selectedSidebarPanel, isPortrait: sidebarArtworkScroll.isPortrait, width: proxy.size.width))
            let bodyHeight = max(0, upperHeight - headerHeight)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    sidebarMainArea(
                        width: proxy.size.width,
                        upperHeight: upperHeight,
                        headerHeight: headerHeight,
                        bodyHeight: bodyHeight
                    )
                    .frame(width: proxy.size.width, height: upperHeight, alignment: .top)
                    .clipped()
                    .windowGestureRegion(.verticalContent)

                    sidebarHeaderBar
                        .frame(width: proxy.size.width, height: headerHeight)
                        .background { sidebarHeaderScrim }
                        .windowGestureRegion(.excluded)
                }
                .frame(width: proxy.size.width, height: upperHeight, alignment: .top)

                PlayerBarView(viewModel: viewModel, router: router, isSidebar: true, sidebarHeight: proxy.size.height, sidebarIsPortrait: sidebarArtworkScroll.isPortrait, sidebarWidth: proxy.size.width,
                              sidebarLyricsPreview: { AnyView(sidebarLyricsPreview(height: max(0, $0))) })
                    .fixedSize(horizontal: false, vertical: true)
                    .windowGestureRegion(.excluded)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: sidebarArtworkScroll.isPortrait)
            .onChange(of: showsLyricsSample(panelHeight: proxy.size.height), initial: true) { _, visible in
                sidebarLyricsPreviewVisible = visible
            }
        }
        .background {
            PlaybackSidebarBackground(palette: sidebarPalette)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        // The shadow belongs to a static shape behind the panel. Applying it to the
        // panel itself would re-rasterize live video, karaoke and scrolling content
        // into an offscreen shadow pass on every frame.
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
                .allowsHitTesting(false)
        }
        .onAppear { sidebarCloseFocused = true }
    }

    private func showsLyricsSample(panelHeight: CGFloat) -> Bool {
        SidebarBottomContent.resolve(sidebarBottomContentRaw) == .lyrics
            && PlaybackSidebarLayout.showsUpcoming(for: panelHeight, panel: viewModel.selectedSidebarPanel,
                                                   isPortrait: sidebarArtworkScroll.isPortrait)
    }

    private var sidebarHeaderBar: some View {
        HStack(spacing: 6) {
            Button { viewModel.closePlaybackSidebar() } label: {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .frame(width: 28, height: 34)
            }
            .focused($sidebarCloseFocused)
            .help(L10n.text("playbackSidebar.close"))
            .accessibilityLabel(L10n.text("playbackSidebar.close"))

            SideBSegmentedControl(
                segments: PlaybackSidebarPanel.allCases.map {
                    SideBControlSegment(id: $0, title: $0.title, symbol: $0.icon)
                }, selection: viewModel.selectedSidebarPanel
            ) { panel in
                viewModel.selectedSidebarPanel = panel
                if panel == .lyrics { selectedPanel = .lyrics }
                if panel == .queue { selectedPanel = .queue }
            }
            .frame(maxWidth: .infinity)

            Button { viewModel.isFullscreenPresented = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 34)
            }
            .help(L10n.text("player.openFullscreen"))
            .accessibilityLabel(L10n.text("player.openFullscreen"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var sidebarHeaderScrim: some View {
        if reduceTransparency || contrast == .increased {
            sidebarTint.overlay(Color.black.opacity(0.42))
        } else {
            LinearGradient(
                colors: [
                    Color.black.opacity(viewModel.selectedSidebarPanel == .artwork ? 0.34 : 0.16),
                    Color.black.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func sidebarMainArea(
        width: CGFloat,
        upperHeight: CGFloat,
        headerHeight: CGFloat,
        bodyHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NowPlayingSidebarArtworkHost(
                    viewModel: viewModel,
                    state: sidebarArtworkScroll,
                    width: width,
                    height: upperHeight,
                    tint: sidebarTint,
                    bottomTint: sidebarBottomTint
                )

                if viewModel.selectedSidebarPanel == .artwork {
                    NativeSidebarRecommendationsView(
                        viewModel: viewModel, router: router, heroHeight: upperHeight,
                        state: sidebarArtworkScroll, occurrenceKey: sidebarArtworkOccurrenceKey
                    )
                }
            }
            .frame(width: width, height: upperHeight, alignment: .top)
            .opacity(viewModel.selectedSidebarPanel == .artwork ? 1 : 0)
            .allowsHitTesting(viewModel.selectedSidebarPanel == .artwork)
            .accessibilityHidden(viewModel.selectedSidebarPanel != .artwork)

            if viewModel.selectedSidebarPanel == .lyrics {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach([false, true], id: \.self) { genius in
                                Button {
                                    viewModel.isShowingGeniusLyrics = genius
                                    if genius { viewModel.genius.ensureNow() }
                                } label: {
                                    Text(genius ? "Genius" : L10n.text("playbackSidebar.synced"))
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(.white.opacity(viewModel.isShowingGeniusLyrics == genius ? 0.15 : 0)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(viewModel.isShowingGeniusLyrics == genius ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 20)
                        lyricsPanel(height: max(0, bodyHeight - 40))
                    }
                    .frame(width: width, height: bodyHeight)
                }
                .frame(width: width, height: upperHeight, alignment: .top)
            } else if viewModel.selectedSidebarPanel == .queue {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerHeight)
                    queuePanel(height: bodyHeight)
                        .padding(.horizontal, 12)
                        .frame(width: width, height: bodyHeight)
                }
                .frame(width: width, height: upperHeight, alignment: .top)
            }
        }
        .frame(width: width, height: upperHeight, alignment: .top)
    }

}
