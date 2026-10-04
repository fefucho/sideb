import SwiftUI

// MARK: - FloatingNavigationCapsule

struct FloatingNavigationCapsule: View {
    @Bindable var router: NavigationRouter
    @State private var isSpinning: Bool = false
    
    var body: some View {
        HStack(spacing: 2) {
            // En la pantalla de Inicio, el botón de Refresh se acopla a la izquierda de [ ◀ ▶ ]
            if router.currentPage == .home {
                Button {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        isSpinning = true
                    }
                    router.refreshHome()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        isSpinning = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                        .frame(width: ShellLayout.navigationControlHeight, height: ShellLayout.navigationControlHeight)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Actualizar recomendaciones (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.7)),
                    removal: .opacity.combined(with: .scale(scale: 0.7))
                ))
                
                Divider()
                    .frame(height: 14)
                    .opacity(0.3)
                    .padding(.horizontal, 1)
                    .transition(.opacity)
            }
            
            // Botón Atrás (◀)
            Button {
                router.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: ShellLayout.navigationControlHeight, height: ShellLayout.navigationControlHeight)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!router.canGoBack)
            .opacity(router.canGoBack ? 1.0 : 0.32)
            .help("Atrás (⌘[)")
            .keyboardShortcut("[", modifiers: .command)
            
            // Botón Adelante (▶)
            Button {
                router.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: ShellLayout.navigationControlHeight, height: ShellLayout.navigationControlHeight)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!router.canGoForward)
            .opacity(router.canGoForward ? 1.0 : 0.32)
            .help("Adelante (⌘])")
            .keyboardShortcut("]", modifiers: .command)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .compatGlass(interactive: true, in: Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: router.currentPage == .home)
    }
}
