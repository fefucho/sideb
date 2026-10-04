import SwiftUI
import AppKit

// MARK: - AppTheme (Side B Design System)

public enum AppTheme {
    // MARK: - Home artwork geometry and surface
    public static let artworkThumbnailRadius: CGFloat = 2
    public static let artworkCardRadius: CGFloat = 5
    public static let artworkHeroRadius: CGFloat = 8
    public static let homeBackground = Color(red: 23/255, green: 23/255, blue: 23/255)
    public static let nsHomeBackground = NSColor(srgbRed: 23/255, green: 23/255, blue: 23/255, alpha: 1.0)

    // MARK: - Acento discreto para superficies seleccionadas
    /// Rojo suave mate (#A33D45): mantiene contraste con texto blanco sin dominar el contenido.
    public static let accent = Color(red: 163/255, green: 61/255, blue: 69/255)
    
    public static let nsAccent = NSColor(srgbRed: 163/255, green: 61/255, blue: 69/255, alpha: 1.0)

    /// Rojo A aclarado (#D06C70) para que los iconos y la línea de progreso sigan visibles sobre el cristal oscuro.
    public static let accentHighlight = Color(red: 208/255, green: 108/255, blue: 112/255)
    
    // MARK: - Content surfaces
    /// Fondo oscuro suave: permite separar el contenido de la barra lateral translúcida.
    public static let darkBackground = Color(red: 27/255, green: 27/255, blue: 30/255)
    
    public static let nsDarkBackground = NSColor(srgbRed: 27/255, green: 27/255, blue: 30/255, alpha: 1.0)
    
    /// Tinte sutil sobre el material de la barra lateral.
    public static let sidebarBackground = Color(red: 36/255, green: 36/255, blue: 42/255)
    
    /// Fondo de tarjetas elevadas sobre el negro profundo.
    public static let cardBackground = Color.white.opacity(0.05)
    
    /// Fondo de tarjetas elevadas en estado hover.
    public static let cardHoverBackground = Color.white.opacity(0.08)
    
    /// Borde sutil continuo para tarjetas y cápsulas en macOS 26/27.
    public static let cardBorder = Color.white.opacity(0.08)
    public static let nsCardBorder = NSColor.white.withAlphaComponent(0.08)
    public static let cardBorderWidth: CGFloat = 0.5

    /// Fondo neutro translúcido elegante para pistas en reproducción activa (reemplaza el fondo rojo estridente).
    public static let activeRowBackground = Color.white.opacity(0.07)
    public static let nsActiveRowBackground = NSColor.white.withAlphaComponent(0.065)
    public static let activeRowBorder = Color.white.opacity(0.09)
    public static let nsActiveRowBorder = NSColor.white.withAlphaComponent(0.09)
}

// MARK: - Color Extensions

public extension Color {
    /// Acento rojo suave mate para selecciones.
    static var sidebAccent: Color { AppTheme.accent }

    static var sidebAccentHighlight: Color { AppTheme.accentHighlight }
    
    /// Fondo oscuro del área de contenido.
    static var sidebDarkBackground: Color { AppTheme.darkBackground }
    
    /// Fondo sutil para tarjetas en reposo.
    static var sidebCardBackground: Color { AppTheme.cardBackground }
    
    /// Borde sutil para tarjetas y cápsulas.
    static var sidebCardBorder: Color { AppTheme.cardBorder }

    /// Fondo para filas activas en reproducción.
    static var sidebActiveRowBackground: Color { AppTheme.activeRowBackground }
    static var sidebActiveRowBorder: Color { AppTheme.activeRowBorder }
}

// MARK: - NSColor Extensions

public extension NSColor {
    /// Acento rojo suave mate en AppKit.
    static var sidebAccent: NSColor { AppTheme.nsAccent }
    
    /// Fondo oscuro del área de contenido en AppKit.
    static var sidebDarkBackground: NSColor { AppTheme.nsDarkBackground }

    /// Borde de tarjeta continuo para AppKit.
    static var sidebCardBorder: NSColor { AppTheme.nsCardBorder }

    /// Fondo para filas activas en reproducción en AppKit.
    static var sidebActiveRowBackground: NSColor { AppTheme.nsActiveRowBackground }
    static var sidebActiveRowBorder: NSColor { AppTheme.nsActiveRowBorder }
}
