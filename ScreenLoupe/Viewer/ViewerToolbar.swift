import AppKit

/// The Viewer's toolbar (TASK.md §15): zoom presets and the current zoom on the left; Copy, Save and
/// the keep-on-top pin on the right.
///
/// Every item has a menu form, so when a narrow window moves items into the overflow (») menu they
/// stay usable: Zoom becomes a submenu of presets, the buttons become commands, the pin a checkmark.
@MainActor
final class ViewerToolbar: NSObject, NSToolbarDelegate {
    private static let presetsID = NSToolbarItem.Identifier("zoomPresets")
    private static let zoomLabelID = NSToolbarItem.Identifier("zoomLabel")
    private static let copyID = NSToolbarItem.Identifier("copyView")
    private static let saveID = NSToolbarItem.Identifier("saveView")
    private static let onTopID = NSToolbarItem.Identifier("alwaysOnTop")

    var onToggleAlwaysOnTop: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    /// Segment 0 is Fit; the rest are `ZoomPanState.presets`.
    private static let presetTitles = ["Fit"] + ZoomPanState.presets.map { "\(Int($0))×" }
    private let presets = NSSegmentedControl(
        labels: presetTitles, trackingMode: .selectOne, target: nil, action: nil)
    private let zoomLabel = NSTextField(labelWithString: "")
    private let onTopButton = NSButton()
    private let copyButton = NSButton()
    private let saveButton = NSButton()

    /// The overflow-menu forms.
    private let presetsMenuItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
    private let zoomLabelMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let onTopMenuItem = NSMenuItem(title: "Keep on Top", action: nil, keyEquivalent: "")

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

        configure(copyButton, symbol: "doc.on.doc", title: "Copy View", action: #selector(copyClicked))
        configure(saveButton, symbol: "square.and.arrow.down", title: "Save View…", action: #selector(saveClicked))
        configure(onTopButton, symbol: "pin", title: "Keep on Top", action: #selector(onTopClicked))
        onTopButton.setButtonType(.pushOnPushOff)
        onTopButton.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on Top")

        let presetsMenu = NSMenu()
        for (index, title) in Self.presetTitles.enumerated() {
            let item = presetsMenu.addItem(withTitle: title, action: #selector(presetMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
        }
        presetsMenuItem.submenu = presetsMenu
        zoomLabelMenuItem.isEnabled = false
        onTopMenuItem.target = self
        onTopMenuItem.action = #selector(onTopClicked)

        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        refresh()
    }

    private func configure(_ button: NSButton, symbol: String, title: String, action: Selector) {
        button.bezelStyle = .toolbar
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = title
        button.target = self
        button.action = action
    }

    /// Reflects the current zoom: the matching preset is selected, and the label shows the percentage.
    func refresh() {
        let state = zoomPan.state
        let percent = "Zoom: \(Int((state.zoom * 100).rounded()))%"
        zoomLabel.stringValue = percent
        zoomLabelMenuItem.title = percent
        let selected: Int
        if zoomPan.isFit {
            selected = 0
        } else if let index = ZoomPanState.presets.firstIndex(where: { abs($0 - state.zoom) < 0.0001 }) {
            selected = index + 1
        } else {
            selected = -1
        }
        presets.selectedSegment = selected
        for item in presetsMenuItem.submenu?.items ?? [] {
            item.state = item.tag == selected ? .on : .off
        }
    }

    func setAlwaysOnTop(_ isOn: Bool) {
        onTopButton.state = isOn ? .on : .off
        onTopMenuItem.state = isOn ? .on : .off
    }

    // MARK: Actions

    @objc private func onTopClicked() { onToggleAlwaysOnTop?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }

    @objc private func presetChosen(_ sender: NSSegmentedControl) {
        choosePreset(sender.selectedSegment)
    }

    @objc private func presetMenuChosen(_ sender: NSMenuItem) {
        choosePreset(sender.tag)
    }

    private func choosePreset(_ index: Int) {
        if index == 0 {
            zoomPan.fit()
        } else if index > 0 {
            zoomPan.setZoom(ZoomPanState.presets[index - 1])
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.presetsID, Self.zoomLabelID, .flexibleSpace, Self.copyID, Self.saveID, Self.onTopID]
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
            item.menuFormRepresentation = presetsMenuItem
        case Self.zoomLabelID:
            item.view = zoomLabel
            item.menuFormRepresentation = zoomLabelMenuItem
        case Self.copyID:
            item.view = copyButton
            item.label = "Copy View"
            item.menuFormRepresentation = commandItem("Copy View", #selector(copyClicked))
        case Self.saveID:
            item.view = saveButton
            item.label = "Save View…"
            item.menuFormRepresentation = commandItem("Save View…", #selector(saveClicked))
        case Self.onTopID:
            item.view = onTopButton
            item.label = "Keep on Top"
            item.menuFormRepresentation = onTopMenuItem
        default:
            return nil
        }
        return item
    }

    private func commandItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
