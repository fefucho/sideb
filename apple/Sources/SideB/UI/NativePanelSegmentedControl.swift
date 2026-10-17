import AppKit
import SwiftUI

/// AppKit owns the tab surface and moving selection. Do not nest its bezel in glass.
struct SideBSegmentedControl<ID: Hashable>: NSViewRepresentable {
    let segments: [SideBControlSegment<ID>]
    let selection: ID
    let onSelect: (ID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NativePanelSegmentHost {
        makeNativeHost(coordinator: context.coordinator, enabled: context.environment.isEnabled)
    }

    func makeNativeHost(coordinator: Coordinator, enabled: Bool = true) -> NativePanelSegmentHost {
        let host = NativePanelSegmentHost(items: segments.map { NativePanelSegmentItem(title: $0.title, symbol: $0.symbol) },
                                          target: coordinator, action: #selector(Coordinator.select(_:)))
        updateNativeHost(host, coordinator: coordinator, enabled: enabled)
        return host
    }

    func updateNSView(_ host: NativePanelSegmentHost, context: Context) {
        updateNativeHost(host, coordinator: context.coordinator, enabled: context.environment.isEnabled)
    }

    func updateNativeHost(_ host: NativePanelSegmentHost, coordinator: Coordinator, enabled: Bool = true) {
        coordinator.parent = self
        host.bar.updateItems(segments.map { NativePanelSegmentItem(title: $0.title, symbol: $0.symbol) })
        let selected = segments.firstIndex { $0.id == selection } ?? (segments.isEmpty ? -1 : 0)
        // A SwiftUI echo of a native click must not restart the moving selection.
        if host.bar.control.selectedSegment != selected { host.bar.control.selectedSegment = selected }
        host.bar.control.isEnabled = enabled
        host.invalidateIntrinsicContentSize()
        host.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativePanelSegmentHost,
                     context: Context) -> CGSize? {
        CGSize(width: nsView.bar.width(fitting: proposal.width), height: SideBControlMetrics.groupHeight)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: SideBSegmentedControl
        init(_ parent: SideBSegmentedControl) { self.parent = parent }

        @objc func select(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard sender.isEnabled, parent.segments.indices.contains(index),
                  sender.isEnabled(forSegment: index) else { return }
            parent.onSelect(parent.segments[index].id)
        }
    }
}

struct NativePanelSegmentItem: Equatable {
    let title: String
    let symbol: String
}

final class NativePanelSegmentHost: NSView {
    let bar: NativePanelSegmentBar

    init(items: [NativePanelSegmentItem], target: AnyObject, action: Selector) {
        bar = NativePanelSegmentBar(items: items, target: target, action: action)
        super.init(frame: .zero)
        addSubview(bar)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        NSSize(width: bar.fullWidth, height: SideBControlMetrics.groupHeight)
    }
    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        bar.setCompact(bounds.width + 0.5 < bar.fullWidth)
        let size = bar.fittingSize
        bar.frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                           width: size.width, height: size.height)
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
    }
}

final class NativePanelSegmentBar: NSView {
    let control: NativePanelSegmentControl
    private var items: [NativePanelSegmentItem] = []
    private var compact = false
    private(set) var fullWidth: CGFloat = 0
    private var compactWidth: CGFloat = 0
    private var nativeControlSize = NSSize.zero

    init(items: [NativePanelSegmentItem], target: AnyObject, action: Selector) {
        control = NativePanelSegmentControl(labels: items.map(\.title), trackingMode: .selectOne, target: target, action: action)
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillProportionally
        // Use AppKit's taller bezel; changing only the frame stretches no artwork.
        if #available(macOS 26.0, *) { control.controlSize = .extraLarge }
        else { control.controlSize = .large }
        control.font = .systemFont(ofSize: 13, weight: .medium)
        if #available(macOS 26.0, *) { control.borderShape = .capsule }
        if #available(macOS 27.0, *) { control.role = .tabs }
        super.init(frame: .zero)
        addSubview(control)
        updateItems(items)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        NSSize(width: compact ? compactWidth : fullWidth, height: SideBControlMetrics.groupHeight)
    }
    override var fittingSize: NSSize { intrinsicContentSize }

    func width(fitting proposal: CGFloat?) -> CGFloat {
        guard let proposal, proposal + 0.5 < fullWidth else { return fullWidth }
        return compactWidth
    }

    func updateItems(_ newItems: [NativePanelSegmentItem]) {
        guard items != newItems else { return }
        items = newItems
        control.segmentCount = items.count
        // Keep stable full/compact proposals during SwiftUI update transactions.
        // AppKit distributes automatic-width segments within the available frame.
        fullWidth = items.reduce(2 * SideBControlMetrics.groupInset) { $0 + segmentWidth($1) }
        // Extra-large tabs need their native horizontal bezel clearance too.
        // A 32pt slot lets the moving lens protrude even when the icon fits.
        let compactSegmentWidth: CGFloat
        if #available(macOS 26.0, *) { compactSegmentWidth = 48 }
        else { compactSegmentWidth = 36 }
        compactWidth = CGFloat(items.count) * compactSegmentWidth + 2 * SideBControlMetrics.groupInset
        applyContent(compact: compact)
        control.setAccessibilityLabel(items.map(\.title).joined(separator: ", "))
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func setCompact(_ value: Bool) {
        guard compact != value else { return }
        compact = value
        applyContent(compact: value)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func applyContent(compact: Bool) {
        for (index, item) in items.enumerated() {
            control.setLabel(compact ? "" : item.title, forSegment: index)
            let image = segmentImage(item)
            control.setImage(image, forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            control.setToolTip(item.title, forSegment: index)
            control.setTag(index, forSegment: index)
            control.setWidth(0, forSegment: index)
        }
        let height = control.cell?.cellSize.height ?? SideBControlMetrics.groupSegmentHeight
        nativeControlSize = NSSize(width: (compact ? compactWidth : fullWidth) - 2 * SideBControlMetrics.groupInset,
                                  height: height > 0 ? height : SideBControlMetrics.groupSegmentHeight)
        control.setFrameSize(nativeControlSize)
    }

    private func segmentImage(_ item: NativePanelSegmentItem) -> NSImage? {
        NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium))
    }

    private func segmentWidth(_ item: NativePanelSegmentItem) -> CGFloat {
        let font = control.font ?? NSFont.systemFont(ofSize: 13, weight: .medium)
        let iconWidth = segmentImage(item)?.size.width ?? 12.5
        return ceil((item.title as NSString).size(withAttributes: [.font: font]).width) + iconWidth + 7 + 2 * 20
    }

    override func layout() {
        super.layout()
        // Preserve the actual native bezel height instead of stretching/scaling it.
        control.frame = NSRect(x: bounds.midX - nativeControlSize.width / 2,
                               y: bounds.midY - nativeControlSize.height / 2,
                               width: nativeControlSize.width, height: nativeControlSize.height)
    }
}

/// Keep the native focus/lens while adding the group's Home/End and wrap behaviour.
final class NativePanelSegmentControl: NSSegmentedControl {
    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        let enabled = (0..<segmentCount).filter { isEnabled(forSegment: $0) }
        guard !enabled.isEmpty else { return }
        let current = enabled.firstIndex(of: selectedSegment) ?? 0
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let index: Int
        switch event.keyCode {
        case 123: index = (current + (rtl ? 1 : -1) + enabled.count) % enabled.count
        case 124: index = (current + (rtl ? -1 : 1) + enabled.count) % enabled.count
        case 115: index = 0
        case 119: index = enabled.count - 1
        default: super.keyDown(with: event); return
        }
        selectedSegment = enabled[index]
        if let action { sendAction(action, to: target) }
    }
}
