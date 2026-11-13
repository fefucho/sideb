import AppKit
import SideBCore

/// What the queue surfaces know about a live Jam. `nil` outside a Jam, so a surface can pass it
/// straight through and compare it cheaply to decide whether to rebuild.
struct JamQueueContext: Equatable {
    let host: String?
    let entries: [JamQueueEntry]

    /// Header text that replaces the playlist/album/radio context while the Jam owns the queue.
    var title: String {
        guard let host, !host.isEmpty else { return L10n.text("jam.live.titleNoHost") }
        return L10n.text("jam.live.title", args: [host])
    }

    static let symbol = "person.2.fill"

    /// The context of the running Jam, read from the controller. Reading it inside a view body
    /// registers observation of the Jam queue, so the surface refreshes when matches arrive.
    @MainActor static func current(for player: PlayerViewModel) -> JamQueueContext? {
        guard player.isJamSessionActive else { return nil }
        let jam = JamSessionController.shared
        return JamQueueContext(host: jam.hostName, entries: jam.queueEntries)
    }
}

/// Who put a track in the Jam queue.
enum JamRowMarker: Equatable {
    case addedByPerson, spotifySuggestion

    init(_ entry: JamQueueEntry) { self = entry.isAddedByPerson ? .addedByPerson : .spotifySuggestion }

    var symbol: String { self == .addedByPerson ? "person.fill" : "sparkles" }
    var label: String {
        L10n.text(self == .addedByPerson ? "jam.queue.addedByPerson" : "jam.queue.spotifySuggestion")
    }
}

/// Pure merge of the Jam queue with the rows mirrored into the app queue. The Jam order is the
/// truth; the app queue only holds the tracks that have a YouTube Music match, with the
/// occurrence identities that drag and drop and the context menus rely on.
enum JamQueueMerge {
    /// The parts of a `JamQueueEntry` the merge needs.
    struct Entry: Equatable {
        let id: String
        let index: Int
        let status: JamQueueEntry.Status
        let videoID: String?

        init(id: String, index: Int, status: JamQueueEntry.Status, videoID: String?) {
            self.id = id; self.index = index; self.status = status; self.videoID = videoID
        }

        init(_ entry: JamQueueEntry) {
            self.init(id: entry.id, index: entry.index, status: entry.status, videoID: entry.song?.videoId)
        }
    }

    /// An upcoming row of the app queue.
    struct Occurrence: Equatable {
        let id: String
        let videoID: String
    }

    enum Item: Equatable {
        /// A playable row. `entry` is the Jam entry it mirrors, `nil` when the mirror could not be
        /// paired reliably (the row is then shown without a marker).
        case occurrence(id: String, entry: Entry?)
        /// A Jam track with no playable row: still resolving, or with no YouTube Music equivalent.
        case placeholder(Entry, resolving: Bool)
    }

    static func merge(entries: [Entry], upcoming: [Occurrence]) -> [Item] {
        let matched = entries.filter { $0.status == .matched }
        let paired = matched.count == upcoming.count
            && zip(matched, upcoming).allSatisfy { $0.videoID == $1.videoID }
        guard paired else {
            // Without a reliable pairing nothing is invented: show what the app queue holds, and
            // only when it holds nothing yet fall back to the Jam list as placeholders.
            if upcoming.isEmpty { return entries.map { .placeholder($0, resolving: $0.status != .unavailable) } }
            return upcoming.map { .occurrence(id: $0.id, entry: nil) }
        }
        var next = upcoming.makeIterator()
        return entries.map { entry in
            guard entry.status == .matched, let row = next.next() else {
                return .placeholder(entry, resolving: entry.status != .unavailable)
            }
            return .occurrence(id: row.id, entry: entry)
        }
    }

    /// Row number shown for a Jam entry: the playing track is 1, the next one 2.
    static func displayNumber(forEntryIndex index: Int) -> Int { index + 2 }
}

/// The few rows the sidebar's "Up next" block shows while a Jam is live.
struct SidebarJamPreviewRow: Identifiable, Equatable {
    let id: String
    let title: String
    let artists: String
    let duration: String?
    let song: SongItemRecord?
    let status: JamQueueEntry.Status
    let marker: JamRowMarker

    static func preview(_ entries: [JamQueueEntry], limit: Int = 2) -> [SidebarJamPreviewRow] {
        entries.prefix(max(0, limit)).map { entry in
            SidebarJamPreviewRow(id: entry.id, title: entry.song?.title ?? entry.track.displayTitle,
                                 artists: entry.song?.displayArtist ?? entry.track.displayArtists,
                                 duration: entry.song?.duration ?? JamDuration.text(milliseconds: entry.track.durationMs),
                                 song: entry.song, status: entry.status, marker: JamRowMarker(entry))
        }
    }
}

enum JamDuration {
    static func text(milliseconds: Double?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let total = Int((milliseconds / 1000).rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// Where the Jam badge sits in the playback sidebar. The header and the artwork card share a
/// fixed 58 pt offset, so there is no room above the card for a pill; it overlays the card's top
/// edge instead and never moves the artwork.
enum JamSidebarBadgePlacement {
    static let headerHeight: CGFloat = 58
    static let inset: CGFloat = 8

    static func top(width: CGFloat, height: CGFloat, portrait: Bool) -> CGFloat {
        if portrait { return headerHeight + inset }
        return SidebarArtworkLayout(width: width, height: height, portrait: false).cardTop + inset
    }
}

// MARK: - Marker badge

/// A small round glyph on the artwork corner: who put the track in the Jam.
final class JamRowMarkerView: NSView {
    private let symbolView = NSImageView()
    static let size: CGFloat = 15

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.size / 2
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.88).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 9),
            symbolView.heightAnchor.constraint(equalToConstant: 9)
        ])
        setAccessibilityRole(.image)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.size, height: Self.size) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ marker: JamRowMarker?) {
        guard let marker else { isHidden = true; toolTip = nil; return }
        isHidden = false
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        symbolView.image = NSImage(systemSymbolName: marker.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        symbolView.contentTintColor = marker == .addedByPerson
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor(calibratedRed: 0.52, green: 0.90, blue: 0.62, alpha: 1)
        toolTip = marker.label
        setAccessibilityLabel(marker.label)
    }
}

// MARK: - Placeholder row

/// A Jam track that cannot be played from here: it is still being matched, or YouTube Music has
/// no equivalent. Same geometry as `NativeQueueTrackCellView`, dimmed, with no actions.
final class JamPlaceholderCellView: NSTableCellView {
    private let indexLabel = NSTextField(labelWithString: "")
    private let artwork = NSView()
    private let artworkIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let marker = JamRowMarkerView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        indexLabel.font = .systemFont(ofSize: 11.5)
        indexLabel.textColor = .tertiaryLabelColor
        indexLabel.alignment = .right
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = AppTheme.artworkThumbnailRadius
        artwork.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        artwork.layer?.borderWidth = 1
        artwork.layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        artworkIcon.imageScaling = .scaleProportionallyDown
        artworkIcon.contentTintColor = NSColor.white.withAlphaComponent(0.38)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.labelColor.withAlphaComponent(0.42)
        titleLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.lineBreakMode = .byTruncatingTail
        durationLabel.font = .systemFont(ofSize: 11.5)
        durationLabel.textColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.7)
        durationLabel.alignment = .center
        for view in [indexLabel, artwork, titleLabel, statusLabel, durationLabel, marker] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for view in [artworkIcon, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            artwork.addSubview(view)
        }
        NSLayoutConstraint.activate([
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 24),
            artwork.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 10),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 36),
            artwork.heightAnchor.constraint(equalToConstant: 36),
            artworkIcon.centerXAnchor.constraint(equalTo: artwork.centerXAnchor),
            artworkIcon.centerYAnchor.constraint(equalTo: artwork.centerYAnchor),
            artworkIcon.widthAnchor.constraint(equalToConstant: 16),
            artworkIcon.heightAnchor.constraint(equalToConstant: 16),
            spinner.centerXAnchor.constraint(equalTo: artwork.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: artwork.centerYAnchor),
            marker.widthAnchor.constraint(equalToConstant: JamRowMarkerView.size),
            marker.heightAnchor.constraint(equalToConstant: JamRowMarkerView.size),
            marker.trailingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 4),
            marker.bottomAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1.5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -12),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1.5),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -12),
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 44)
        ])
        // Keep long titles compressing before the fixed columns do.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        spinner.stopAnimation(nil)
        marker.apply(nil)
    }

    func configure(entry: JamQueueEntry, resolving: Bool) {
        indexLabel.stringValue = "\(JamQueueMerge.displayNumber(forEntryIndex: entry.index))"
        let artists = entry.track.displayArtists
        let title = NSMutableAttributedString(string: entry.track.displayTitle)
        if !artists.isEmpty {
            title.append(NSAttributedString(string: "  " + artists, attributes: [
                .foregroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.8),
                .font: NSFont.systemFont(ofSize: 12)
            ]))
        }
        titleLabel.attributedStringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        let status = L10n.text(resolving ? "jam.queue.resolving" : "jam.queue.unavailable")
        statusLabel.stringValue = status
        statusLabel.textColor = resolving
            ? NSColor.secondaryLabelColor.withAlphaComponent(0.75)
            : NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.42, alpha: 0.9)
        durationLabel.stringValue = JamDuration.text(milliseconds: entry.track.durationMs) ?? ""
        if resolving {
            artworkIcon.isHidden = true
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            artworkIcon.isHidden = false
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            artworkIcon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
        let marking = JamRowMarker(entry)
        marker.apply(marking)
        let summary = [entry.track.displayTitle, artists, status, marking.label].filter { !$0.isEmpty }.joined(separator: ", ")
        toolTip = summary
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(summary)
    }
}
