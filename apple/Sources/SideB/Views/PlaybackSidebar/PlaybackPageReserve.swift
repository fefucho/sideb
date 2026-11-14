import SwiftUI

/// Reserva de la pagina junto al panel Ahora suena, leida aqui y no en la raiz de la ventana: durante el arrastre solo
/// se re-evalua este modificador (con `pageWidth`, a <= 1 vez por fotograma); el contenido de la pagina no se reconstruye.
struct PlaybackPageReserve: ViewModifier {
    let model: PlaybackPanelResizeModel
    let storedWidth: CGFloat
    let windowWidth: CGFloat
    let presented: Bool

    func body(content: Content) -> some View {
        let width = PlaybackSidebarLayout.effectiveWidth(stored: model.pageWidth ?? storedWidth, windowWidth: windowWidth, leftReserve: 0)
        content.padding(.trailing, PlaybackSidebarLayout.contentReserve(windowWidth: windowWidth, leftReserve: 0,
                                                                         presented: presented, panelWidth: width))
    }
}
