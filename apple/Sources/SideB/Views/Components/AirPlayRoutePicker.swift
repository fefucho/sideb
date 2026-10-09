import SwiftUI
import AVKit
import AppKit

/// Representación AppKit nativa de AVRoutePickerView para macOS.
/// Proporciona el selector nativo del sistema para salidas de audio AirPlay 2 y Bluetooth.
struct AirPlayRoutePickerView: NSViewRepresentable {
    init() {}

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
        AirPlayRoutePickerView()
            .frame(width: 32, height: 32)
            .help(L10n.text("app.audioOutput"))
    }
}
