import SwiftUI
import AppKit

// MARK: - DescriptionCardModal

/// Modal flotante Liquid Glass para lectura expandida de descripciones y biografías.
/// Permite cerrar haciendo clic en cualquier área exterior, pulsando la tecla Escape
/// o mediante el botón "X" en la esquina superior derecha.
public struct DescriptionCardModal: View {
    public let title: String
    public let subtitle: String?
    public let description: String
    @Binding public var isPresented: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        description: String,
        isPresented: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            // Fondo atenuado (Click-outside para cerrar)
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeModal()
                }

            // Tarjeta Liquid Glass Flotante
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let subtitle = subtitle, !subtitle.isEmpty {
                            Text(subtitle.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(1.0)
                        }

                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 16)

                    Button {
                        closeModal()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(L10n.text("common.closeEscape"))
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                // Scroll con el texto íntegro
                ScrollView(.vertical, showsIndicators: true) {
                    Text(description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 4)
                }
                .frame(minHeight: 120, maxHeight: 320)
            }
            .padding(24)
            .frame(maxWidth: 540)
            .compatGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 32, x: 0, y: 14)
            .padding(.horizontal, 32)
            // Detener propagación de toques dentro de la tarjeta
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {
                // No-op: Evita que taps dentro cierren el modal
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func closeModal() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
