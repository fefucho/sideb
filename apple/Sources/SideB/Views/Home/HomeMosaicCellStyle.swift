import AppKit

/// Medidas de la celda de canción del mosaico por tamaño (variables CSS de `.mosaic` en MediaCard.svelte).
struct HomeMosaicCellStyle: Equatable {
    let inset: CGFloat
    let bottom: CGFloat
    let titleSize: CGFloat
    let titleLineHeight: CGFloat
    let titleWeight: NSFont.Weight
    let titleTracking: CGFloat
    let artistSize: CGFloat
    let artistLineHeight: CGFloat
    let playDiameter: CGFloat
    let playGap: CGFloat
    /// Fracción de la altura de la celda que cubre el degradado inferior.
    let gradientFraction: CGFloat
    let barHeight: CGFloat
    let barWidth: CGFloat
    let barGap: CGFloat
    /// Desplazamiento del título a la derecha cuando suena la canción.
    let barsShift: CGFloat

    static func make(_ size: HomeMosaicSize) -> HomeMosaicCellStyle {
        switch size {
        case .small:
            HomeMosaicCellStyle(inset: 10, bottom: 9, titleSize: 13, titleLineHeight: 16, titleWeight: .semibold,
                titleTracking: 0, artistSize: 11.5, artistLineHeight: 15, playDiameter: 30, playGap: 8,
                gradientFraction: 0.72, barHeight: 11, barWidth: 2.5, barGap: 2, barsShift: 17.5)
        case .wide:
            HomeMosaicCellStyle(inset: 12, bottom: 11, titleSize: 16, titleLineHeight: 20, titleWeight: .bold,
                titleTracking: 0, artistSize: 12.5, artistLineHeight: 16, playDiameter: 32, playGap: 10,
                gradientFraction: 0.72, barHeight: 13, barWidth: 3, barGap: 2, barsShift: 19)
        case .large:
            HomeMosaicCellStyle(inset: 16, bottom: 14, titleSize: 22, titleLineHeight: 27, titleWeight: .bold,
                titleTracking: -0.2, artistSize: 14, artistLineHeight: 19, playDiameter: 40, playGap: 14,
                gradientFraction: 0.52, barHeight: 16, barWidth: 3.5, barGap: 2.5, barsShift: 21.5)
        }
    }

    /// Ancho de las tres barras del ecualizador en línea.
    var barsWidth: CGFloat { 3 * barWidth + 2 * barGap }
    /// Reserva a la derecha cuando Play se ve.
    var playReserve: CGFloat { playDiameter + 14 }
}
