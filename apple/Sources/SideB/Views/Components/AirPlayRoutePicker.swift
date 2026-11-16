import SwiftUI
import AVKit
import AppKit

/// Representación AppKit nativa de AVRoutePickerView para macOS.
/// Proporciona el selector nativo del sistema para salidas de audio AirPlay 2 y Bluetooth.
struct AirPlayRoutePickerView: NSViewRepresentable {
    /// `AudioPlayerService.playerEpoch`: cambia cuando el empalme de Automix sustituye al `AVPlayer` activo,
    /// para que SwiftUI vuelva a llamar a `updateNSView` y el selector siga al reproductor nuevo.
    var playerEpoch = 0
    init(playerEpoch: Int = 0) { self.playerEpoch = playerEpoch }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(NSColor.white.withAlphaComponent(0.70), for: .normal)
        picker.setRoutePickerButtonColor(NSColor.white, for: .normalHighlighted)
        picker.setRoutePickerButtonColor(.white, for: .active)
        picker.setRoutePickerButtonColor(.white, for: .activeHighlighted)
        picker.player = AudioPlayerService.shared.avPlayer
        return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        nsView.player = AudioPlayerService.shared.avPlayer
    }
}

/// Botón nativo de AirPlay sin rebordes, del mismo tamaño y estilo que los demás controles.
struct AirPlayButton: View {
    init() {}

    public var body: some View {
        AirPlayRoutePickerView(playerEpoch: AudioPlayerService.shared.playerEpoch)
            .frame(width: 32, height: 32)
            .help(L10n.text("app.audioOutput"))
    }
}
