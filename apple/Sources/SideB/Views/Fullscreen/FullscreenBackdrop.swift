import SwiftUI

/// Foreground-only canvas. The persistent backdrop belongs to WindowRootView,
/// outside this conditional presentation and its slide transition.
struct FullscreenCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: PlayerViewModel
    @Binding var isSidebarExpanded: Bool
    let router: NavigationRouter?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if viewModel.isFullscreenPresented {
                    FullscreenNowPlayingView(viewModel: viewModel, canvasSize: proxy.size,
                                             sidebarProgress: isSidebarExpanded ? 1 : 0, router: router)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(viewModel.isFullscreenPresented)
        .accessibilityHidden(!viewModel.isFullscreenPresented)
    }
}

/// One noninteractive artwork background across the whole window, behind both
/// columns and the floating sidebar. Its viewport does not resize with the sidebar.
struct FullscreenBackdrop: View {
    let thumbnail: String?
    let trackID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.sidebDarkBackground
                if let thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 300) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 300, height: 300)) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.4)
                            .blur(radius: 75)
                            .overlay(Color.black.opacity(0.72))
                    } placeholder: {
                        Color.sidebDarkBackground
                    }
                    .id("blur_\(trackID ?? url.absoluteString)")
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.07, green: 0.07, blue: 0.08), Color.sidebDarkBackground],
                        startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
