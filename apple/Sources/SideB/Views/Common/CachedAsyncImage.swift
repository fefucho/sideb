import SwiftUI
import AppKit

private struct CachedImageRequest: Equatable {
    let url: URL?
    let targetSize: CGSize
    let active: Bool
}

/// Vista de imagen asíncrona respaldada por `ImageCache`.
/// - Comprobación sincrónica en RAM (`NSCache`) durante la creación inicial para 0ms de latencia al scrollear a 120 FPS.
/// - Decodificación y downsampling en segundo plano sin bloquear el hilo principal ni CoreAnimation.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize = .init(width: 320, height: 320)
    var onFailure: (@MainActor () -> Void)?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedUrl: URL?
    @State private var loadedImage: NSImage?
    @Environment(\.sideBPageIsActive) private var pageIsActive

    init(
        url: URL?,
        targetSize: CGSize = .init(width: 320, height: 320),
        onFailure: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.onFailure = onFailure
        self.content = content
        self.placeholder = placeholder

        // Fast-path sincrónico: si la imagen ya reside en RAM, se inicializa al instante sin frame blanco
        if let url, let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: targetSize) {
            self._loadedImage = State(initialValue: cached)
            self._loadedUrl = State(initialValue: url)
        } else {
            self._loadedImage = State(initialValue: nil)
            self._loadedUrl = State(initialValue: url)
        }
    }

    private var request: CachedImageRequest {
        CachedImageRequest(url: self.url, targetSize: self.targetSize, active: pageIsActive)
    }

    var body: some View {
        let activeImage: NSImage? = {
            guard let url = self.url else { return nil }
            // 1. Si coincide con la URL actualmente cargada en este estado
            if loadedUrl == url, let loadedImage {
                return loadedImage
            }
            // 2. Fast-path sincrónico en memoria RAM para esta URL específica
            return ImageCache.shared.imageFromMemoryCache(for: url, targetSize: self.targetSize)
        }()

        ZStack {
            if let activeImage {
                self.content(Image(nsImage: activeImage))
            } else {
                self.placeholder()
            }
        }
        .task(id: self.request) {
            let req = self.request
            guard req.active else { return }
            guard let url = req.url else {
                self.loadedImage = nil
                self.loadedUrl = nil
                return
            }

            // Si la imagen ya reside en RAM para ESTA URL específica, evitar trabajo de red
            if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: req.targetSize) {
                self.loadedImage = cached
                self.loadedUrl = url
                return
            }

            // Si cambió la URL y no está en RAM, limpiamos la carátula vieja de inmediato para evitar que quede congelada
            if self.loadedUrl != url {
                self.loadedImage = nil
                self.loadedUrl = url
            }

            let loaded = await ImageCache.shared.image(for: url, targetSize: req.targetSize)
            guard !Task.isCancelled, self.request == req else { return }

            if let loaded {
                self.loadedImage = loaded
                self.loadedUrl = url
            } else {
                self.loadedImage = nil
                self.loadedUrl = url
                self.onFailure?()
            }
        }
    }
}
