import AppKit

/// A stable native toolbar host whose child aligns in window coordinates.
/// Bounds remain at the child's natural size so AppKit converts hits at scale.
final class WindowAlignedToolbarContainer: NSView {
    let contentView: NSView
    let scale: CGFloat
    let topInset: CGFloat
    let leadingInset: CGFloat?
    let trailingInset: CGFloat?
    private var resizeObserver: NSObjectProtocol?
    private var naturalSize: CGSize
    private var layingOut = false
    var usesWindowAlignment = true
    var presentationOffset: CGFloat = 0 {
        didSet {
            guard oldValue != presentationOffset else { return }
            needsLayout = true
            superview?.needsLayout = true
        }
    }

    init(contentView: NSView, scale: CGFloat = 1, topInset: CGFloat = 21,
         leadingInset: CGFloat? = nil, trailingInset: CGFloat? = nil) {
        self.contentView = contentView
        self.scale = max(0.01, scale)
        self.topInset = topInset
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        naturalSize = contentView.fittingSize
        if naturalSize.width <= 0 || naturalSize.height <= 0 {
            naturalSize = contentView.frame.size
        }
        super.init(frame: .zero)
        wantsLayer = true
        contentView.wantsLayer = true
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentView.autoresizingMask = []
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: naturalSize.width * scale + (leadingInset ?? 0) + (trailingInset ?? 0), height: ShellLayout.toolbarHostHeight)
    }

    /// Ask the unscaled child for its current fitting size, never its scaled frame.
    func refreshNaturalSize() {
        var size = contentView.fittingSize
        let intrinsic = contentView.intrinsicContentSize
        if size.width <= 0 { size.width = intrinsic.width > 0 ? intrinsic.width : naturalSize.width }
        if size.height <= 0 { size.height = intrinsic.height > 0 ? intrinsic.height : naturalSize.height }
        guard size.width > 0, size.height > 0, size != naturalSize else { return }
        naturalSize = size
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        if let window {
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in self?.needsLayout = true }
        }
        needsLayout = true
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    override func layout() {
        super.layout()
        if !usesWindowAlignment {
            let embeddedSize = contentView.fittingSize
            contentView.frame = CGRect(origin: .zero, size: embeddedSize)
            contentView.bounds = CGRect(origin: .zero, size: embeddedSize)
            return
        }
        guard !layingOut, let windowContent = window?.contentView,
              naturalSize.width > 0, naturalSize.height > 0 else { return }
        layingOut = true
        defer { layingOut = false }
        let size = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let windowRect = ShellLayout.toolbarControlFrame(
            size: size, windowBounds: windowContent.bounds,
            hostRect: windowContent.convert(bounds, from: self), isFlipped: windowContent.isFlipped,
            topInset: topInset, leadingInset: leadingInset, trailingInset: trailingInset
        )
        let translated = windowRect.offsetBy(dx: 0, dy: windowContent.isFlipped ? presentationOffset : -presentationOffset)
        let target = convert(translated, from: windowContent)
        // Keep drawing and hit testing inside the native item's actual host.
        guard bounds.contains(target) else { return }
        if contentView.frame != target { contentView.frame = target }
        contentView.bounds = CGRect(origin: .zero, size: naturalSize)
    }
}
