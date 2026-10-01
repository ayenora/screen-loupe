import AppKit

/// The zoom panel's toolbar style: the zoom presets and field (`ZoomControls`) side by side in a
/// strip under the Viewer's toolbar, centred in it.
///
/// A titlebar accessory, so it sits in the titlebar's material with the toolbar, over none of the
/// image, stays with it in full screen, and never goes into the toolbar's overflow menu.
@MainActor
final class ViewerZoomStrip: NSTitlebarAccessoryViewController {
    /// Above and below the groups.
    private static let margin: CGFloat = 4
    /// Beside the groups, as the toolbar's items keep from the window's edge: the least room a narrow
    /// window leaves them.
    private static let leading: CGFloat = 12

    let controls: ZoomControls

    init(zoomPan: ZoomPanController) {
        controls = ZoomControls(
            zoomPan: zoomPan, orientation: .horizontal,
            insets: NSEdgeInsets(top: Self.margin, left: Self.leading, bottom: Self.margin, right: Self.leading))
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .bottom
        // Adjusted automatically, the strip takes a height of its own; it keeps the groups' and its margins.
        automaticallyAdjustsSize = false
        let height = ToolbarLook.current.buttonSize.height + 2 * Self.margin
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: height))
        // Centred; a window too narrow for that keeps them at its left edge.
        let centred = controls.centerXAnchor.constraint(equalTo: strip.centerXAnchor)
        centred.priority = .defaultHigh
        controls.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: strip.leadingAnchor),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: strip.trailingAnchor),
            centred,
            controls.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
            strip.heightAnchor.constraint(equalToConstant: height),
        ])
        view = strip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
