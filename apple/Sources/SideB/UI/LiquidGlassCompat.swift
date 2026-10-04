import AppKit
import SwiftUI

// MARK: - CompatGlassTransition

public enum CompatGlassTransition {
    case materialize
}

// MARK: - View Extensions

public extension View {
    func compatGlass(interactive: Bool = false, tint: Color? = nil, in shape: some Shape) -> some View {
        self.modifier(CompatGlassModifier(interactive: interactive, tint: tint, shape: shape))
    }

    func compatGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        self.modifier(CompatGlassIDModifier(id: id, namespace: namespace))
    }

    func compatGlassTransition(_ transition: CompatGlassTransition) -> some View {
        self.modifier(CompatGlassTransitionModifier(transition: transition))
    }

    /// Aplica `.glassProminent` en macOS 26/27+, `.borderedProminent` fallback en macOS 15.
    func compatGlassProminentButton() -> some View {
        self.modifier(CompatGlassProminentButtonModifier())
    }

    /// Otorga a la barra lateral una apariencia traslúcida y fluida Liquid Glass.
    func compatTranslucentSidebar() -> some View {
        self.modifier(CompatTranslucentSidebarModifier())
    }
}

// MARK: - CompatGlassModifier

public struct CompatGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var controlActiveState

    public let interactive: Bool
    public var tint: Color?
    public let shape: S

    public init(interactive: Bool = false, tint: Color? = nil, shape: S) {
        self.interactive = interactive
        self.tint = tint
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: self.shape)
        } else if controlActiveState == .inactive {
            content.background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: self.shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(self.glass, in: self.shape)
        } else if let tint {
            content
                .background(tint.opacity(0.55), in: self.shape)
                .background(.ultraThinMaterial, in: self.shape)
        } else {
            content.background(.ultraThinMaterial, in: self.shape)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if self.interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

// MARK: - CompatGlassIDModifier

public struct CompatGlassIDModifier: ViewModifier {
    public let id: String
    public let namespace: Namespace.ID

    public init(id: String, namespace: Namespace.ID) {
        self.id = id
        self.namespace = namespace
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffectID(self.id, in: self.namespace)
        } else {
            content
        }
    }
}

// MARK: - CompatGlassTransitionModifier

public struct CompatGlassTransitionModifier: ViewModifier {
    public let transition: CompatGlassTransition

    public init(transition: CompatGlassTransition) {
        self.transition = transition
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            switch self.transition {
            case .materialize:
                content.glassEffectTransition(.materialize)
            }
        } else {
            content
        }
    }
}

// MARK: - CompatGlassProminentButtonModifier

public struct CompatGlassProminentButtonModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - CompatGlassContainer

public struct CompatGlassContainer<Content: View>: View {
    public var spacing: CGFloat = 0
    @ViewBuilder public var content: () -> Content

    public init(spacing: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: self.spacing) { self.content() }
        } else {
            self.content()
        }
    }
}

// MARK: - CompatTranslucentSidebarModifier

public struct CompatTranslucentSidebarModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                SidebarVisualEffect()
            }
    }
}

private struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension ToolbarContent {
    /// These items supply their own glass, so the native toolbar must not add
    /// another shared plate behind them (including when their view is hidden).
    @ToolbarContentBuilder
    func compatToolbarBackgroundHidden() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}


extension View {
    @ViewBuilder
    func compatScrollEdgesHidden() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}
