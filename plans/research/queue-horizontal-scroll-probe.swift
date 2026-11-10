import AppKit

// Standalone geometry probe; no app, account, stream or project module required.
// Run: swift plans/research/queue-horizontal-scroll-probe.swift
for plain in [false, true] {
    for locked in [false, true] {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        if locked { scroll.horizontalScrollElasticity = .none }
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 46
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if plain { table.style = .plain }
        let column = NSTableColumn(identifier: .init("queue"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        for width in [600.0, 350.0, 600.0] {
            scroll.setFrameSize(NSSize(width: width, height: 300))
            column.width = max(1, scroll.contentSize.width)
            scroll.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            var proposed = clip.bounds
            proposed.origin.x = 20
            print("style=\(plain ? "plain" : "automatic") locked=\(locked) viewport=\(clip.bounds.width) document=\(table.frame.width) overflow=\(table.frame.width - clip.bounds.width) constrainedX=\(clip.constrainBoundsRect(proposed).origin.x)")
        }
    }
}
