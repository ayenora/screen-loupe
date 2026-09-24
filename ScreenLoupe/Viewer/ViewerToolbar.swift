import AppKit

/// The Viewer's toolbar: zoom presets and the current zoom on the left (TASK.md §15), the
/// keep-on-top pin on the right.
@MainActor
final class ViewerToolbar: NSObject, NSToolbarDelegate {
    private static let presetsID = NSToolbarItem.Identifier("zoomPresets")
    private static let zoomLabelID = NSToolbarItem.Identifier("zoomLabel")
    private static let onTopID = NSToolbarItem.Identifier("alwaysOnTop")

    /// Called when the pin is clicked.
    var onToggleAlwaysOnTop: (() -> Void)?

    /// Segment 0 is Fit; the rest are `ZoomPanState.presets`.
    private let presets = NSSegmentedControl(
        labels: ["Fit"] + ZoomPanState.presets.map { "\(Int($0))×" },
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let zoomLabel = NSTextField(labelWithString: "")
    private let onTopButton = NSButton()
    private let zoomPan: ZoomPanController
    let toolbar = NSToolbar(identifier: "Viewer")

    init(zoomPan: ZoomPanController) {
        self.zoomPan = zoomPan
        super.init()
        presets.target = self
        presets.action = #selector(presetChosen(_:))
        presets.segmentStyle = .separated
        for index in 0..<presets.segmentCount {
            presets.setWidth(index == 0 ? 40 : 34, forSegment: index)
        }
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        onTopButton.bezelStyle = .toolbar
        onTopButton.setButtonType(.pushOnPushOff)
        onTopButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Keep on Top")
        onTopButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on Top")
        onTopButton.toolTip = "Keep on Top"
        onTopButton.target = self
        onTopButton.action = #selector(onTopClicked)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        refresh()
    }

    /// Reflects the current zoom: the matching preset is selected, and the label shows the percentage.
    func refresh() {
        let state = zoomPan.state
        zoomLabel.stringValue = "Zoom: \(Int((state.zoom * 100).rounded()))%"
        if zoomPan.isFit {
            presets.selectedSegment = 0
        } else if let index = ZoomPanState.presets.firstIndex(where: { abs($0 - state.zoom) < 0.0001 }) {
            presets.selectedSegment = index + 1
        } else {
            presets.selectedSegment = -1
        }
    }

    func setAlwaysOnTop(_ isOn: Bool) {
        onTopButton.state = isOn ? .on : .off
    }

    @objc private func onTopClicked() {
        onToggleAlwaysOnTop?()
    }

    @objc private func presetChosen(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            zoomPan.fit()
        } else if sender.selectedSegment > 0 {
            zoomPan.setZoom(ZoomPanState.presets[sender.selectedSegment - 1])
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.presetsID, Self.zoomLabelID, .flexibleSpace, Self.onTopID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.presetsID:
            item.view = presets
            item.label = "Zoom"
        case Self.zoomLabelID:
            item.view = zoomLabel
        case Self.onTopID:
            item.view = onTopButton
            item.label = "Keep on Top"
            item.toolTip = "Keep on Top"
        default:
            return nil
        }
        return item
    }
}
