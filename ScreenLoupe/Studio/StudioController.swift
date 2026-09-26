import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// The Screenshot studio (docs/product.md, Screenshot studio): its frame, its palette, Capture,
/// Copy and Save, the frame's sizes and Aspect Lock, the timer, what pictures leave out and lay
/// under, the pointer, and One Window.
/// Shown and hidden on its own, apart from the Viewer and the Capture Area.
///
/// The frame is a `CaptureAreaController` of kind `.studio`: the Capture Area's window, drawing,
/// dragging and snapping, without its locks. The palette is a separate panel, parked anywhere.
@MainActor
final class StudioController {
    /// Called when a capture needs Screen Recording access: the Viewer explains and asks for it.
    /// `deniedByCapture`: ScreenCaptureKit refused although the preflight check said yes.
    var onNeedsPermission: ((_ deniedByCapture: Bool) -> Void)?
    /// The numbers of the app's windows a picture keeps — the Viewer and the Capture Area frame;
    /// every other window of the app is left out.
    var capturedAppWindows: (() -> [Int])?
    /// The Viewer's window number, while it has a window: a left-out window behind it isn't dimmed.
    var viewerWindowNumber: (() -> Int?)?

    private let frame: CaptureAreaController
    private let palette = StudioPalette()
    private let settings: SettingsStore
    private let permissions: PermissionsManager
    private let export: ExportController
    private let log = Logger(category: "studio")
    /// A capture is on its way; presses meanwhile are ignored.
    private var isCapturing = false
    /// The last save panel; while it is open, the commands bring it forward instead.
    private var savePanel: NSSavePanel?
    /// The Size, the Timer or the Background list beside the palette, and which of them it shows.
    private let listPanel = StudioListPanel()
    private enum ListKind { case sizes, timer, background }
    private var shownList: ListKind?
    /// Built the first time Custom Size… is chosen, then kept.
    private var customSizesWindow: NSPanel?
    /// Windows of other apps left out by pointing: for this session only, never saved.
    private var leftOutWindows: Set<CGWindowID> = [] {
        didSet { if leftOutWindows != oldValue { updateDimmed() } }
    }
    /// Picks windows to leave out while it runs.
    private var windowPicker: WindowPicker?
    private let dimOverlay = StudioDimOverlay()
    /// Follows the left-out windows while any are left out and the studio shows.
    private var dimTimer: Timer?
    private var dimTicks = 0
    private let colorTarget = ColorPanelTarget()
    /// The decoded background image, by its file name.
    private var backgroundImage: (fileName: String, maxPixelSize: PixelSize, image: CGImage)?
    /// Where the chosen background image is copied, in the app's container.
    private let backgroundFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.bundleIdentifier ?? "Screen Loupe").appending(path: "Studio")

    init(settings: SettingsStore, permissions: PermissionsManager, export: ExportController) {
        self.settings = settings
        self.permissions = permissions
        self.export = export
        frame = CaptureAreaController(settings: settings, kind: .studio) {
            StudioPlacement.defaultFrame(in: $0, paletteWidth: StudioPalette.width)
        }
        // A window picked with Aspect Lock on gives the lock its ratio, as a size does.
        frame.onPickWindow = { [weak self] in
            self?.advance(.pickerStarted)
            self?.frame.pickWindow { self?.retakeAspectRatio() }
        }
        palette.onCapture = { [weak self] in self?.capture() }
        palette.onCopy = { [weak self] in self?.copy() }
        palette.onSave = { [weak self] in self?.save() }
        palette.onSize = { [weak self] in self?.showSizes(beside: $0) }
        palette.onToggleAspectLock = { [weak self] in self?.toggleAspectLock() }
        palette.onTimer = { [weak self] in self?.showDelays(beside: $0) }
        palette.onBackground = { [weak self] in self?.showBackgrounds(beside: $0) }
        palette.onToggleLeaveOutWindows = { [weak self] in self?.toggleLeavingOutWindows() }
        palette.onToggleOneWindow = { [weak self] in self?.toggleOneWindow() }
        palette.onToggleLeaveOutDock = { [weak self] in self?.toggleLeaveOutDock() }
        palette.onTogglePointer = { [weak self] in self?.togglePointer() }
        palette.onToggleOnTop = { [weak self] in self?.toggleKeepOnTop() }
        palette.onHide = { [weak self] in self?.hide() }
        palette.onDragStarted = { [weak self] in self?.listPanel.dismiss() }
        palette.onMoved = { [weak self] in
            guard let self else { return }
            settings.update { $0.studioPaletteOrigin = self.palette.frame.origin }
        }
        settings.observe(\.studioOnTop) { [weak self] in self?.palette.keepsOnTop = $0 }
        settings.observe(\.studioAspectLocked) { [weak self] in self?.palette.aspectLocked = $0 }
        settings.observe(\.activeStudioAspectRatio) { [weak self] in self?.frame.aspectRatio = $0.map { CGFloat($0) } }
        settings.observe(\.studioLeavesOutDock) { [weak self] in self?.palette.leavesOutDock = $0 }
        settings.observe(\.studioBackground) { [weak self] in self?.palette.hasBackground = $0 != .screen }
        settings.observe(\.studioDelay) { [weak self] in self?.palette.hasDelay = $0 != .off }
        settings.observe(\.studioIncludesPointer) { [weak self] in self?.palette.includesPointer = $0 }
        // The dimmed windows and the countdown move with the frame.
        frame.onChange = { [weak self] in
            self?.updateDimmed()
            self?.updateCountdownPanel()
        }
        colorTarget.onChange = { [weak self] color in
            let srgb = color.usingColorSpace(.sRGB) ?? .white
            let chosen = BackgroundColor(
                clampingRed: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
            self?.settings.update { $0.studioBackground = .color(chosen) }
        }
    }

    // MARK: Visibility

    var isVisible: Bool { frame.isVisible }

    /// Shows the frame where it was, or centred on the main display the first time, and the palette
    /// where it was, or beside the frame.
    func show() {
        frame.show()
        if !palette.isVisible { placePalette() }
        palette.orderFrontRegardless()
        dropClosedWindows()
        updateDimmed()
        checkOneWindow()
        updateOneWindowTimer()
    }

    func hide() {
        listPanel.dismiss()
        windowPicker?.stop()
        frame.hide()
        palette.orderOut(nil)
        updateDimmed()
        advance(.hidden)
        send(.hidden)
        updateOneWindowTimer()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    var keepsOnTop: Bool { settings.settings.studioOnTop }

    func toggleKeepOnTop() {
        settings.update { $0.studioOnTop.toggle() }
    }

    // MARK: Sizes

    /// The frame's size in pixels of its display, for the checkmark in the size lists.
    var pixelSize: PixelSize? { frame.pixelSize }

    /// Gives the frame `size` pixels (`CaptureAreaController.resize(toPixels:)`), unless its display
    /// can't hold them. With Aspect Lock on, the lock takes the frame's ratio.
    func applySize(_ size: PixelSize) {
        guard isVisible else { return }
        if frame.resize(toPixels: size) { retakeAspectRatio() }
    }

    /// With Aspect Lock on, the lock keeps the frame's ratio from now on.
    private func retakeAspectRatio() {
        guard settings.settings.studioAspectLocked else { return }
        let ratio = frameRatio
        settings.update { $0.studioAspectRatio = ratio }
    }

    /// Turning Aspect Lock on takes the frame's current ratio.
    func toggleAspectLock() {
        let ratio = frameRatio
        settings.update {
            $0.studioAspectLocked.toggle()
            if $0.studioAspectLocked { $0.studioAspectRatio = ratio }
        }
    }

    /// Width over height, in pixels of the frame's display.
    private var frameRatio: Double {
        if let size = frame.pixelSize { return Double(size.width) / Double(size.height) }
        return Double(frame.captureRect.width / frame.captureRect.height)
    }

    /// The Size list beside the palette's Size button, or closes it while it shows. Nothing is
    /// activated.
    private func showSizes(beside button: NSView) {
        toggleList(.sizes, beside: button) {
            StudioSizeList(
                current: frame.pixelSize, custom: settings.settings.studioCustomSizes,
                apply: { [weak self] size in
                    self?.listPanel.dismiss()
                    self?.applySize(size)
                },
                editCustomSizes: { [weak self] in
                    self?.listPanel.dismiss()
                    self?.showCustomSizes()
                })
        }
    }

    /// Shows `list` in the list panel beside `button`, or closes the panel when it already shows
    /// that list; another list in it is replaced.
    private func toggleList<List: View>(_ kind: ListKind, beside button: NSView, _ list: () -> List) {
        if listPanel.isVisible, shownList == kind {
            listPanel.dismiss()
            return
        }
        listPanel.dismiss()
        shownList = kind
        let paletteFrame = palette.frame
        let anchorTop = palette.convertToScreen(button.convert(button.bounds, to: nil)).maxY
        let visible = palette.screen?.visibleFrame ?? paletteFrame
        listPanel.show(list(), beside: palette) {
            StudioPlacement.popoverOrigin(size: $0, beside: paletteFrame, anchorTop: anchorTop, in: visible)
        }
    }

    /// The Custom Sizes window: four slots for sizes of the user's own. A non-activating panel, so
    /// opening it from the palette leaves the app the user works in active and brings no other
    /// window of this app forward; it becomes key for typing. At the normal level, so other apps'
    /// windows can cover it. Its content is made anew each time it opens: an edit not taken with
    /// Enter is dropped with it.
    func showCustomSizes() {
        let window = customSizesWindow ?? makeCustomSizesWindow()
        customSizesWindow = window
        if !window.isVisible {
            let host = NSHostingController(
                rootView: CustomSizesView(store: settings) { [weak window] in window?.performClose(nil) })
            host.sizingOptions = .preferredContentSize
            window.contentViewController = host
            window.center()
        }
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func makeCustomSizesWindow() -> NSPanel {
        let window = NSPanel(
            contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: true)
        window.title = "Custom Sizes"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.level = .normal
        window.hidesOnDeactivate = true
        return window
    }

    // MARK: Timer

    var delay: StudioDelay { settings.settings.studioDelay }

    func chooseDelay(_ delay: StudioDelay) {
        settings.update { $0.studioDelay = delay }
    }

    /// The Timer list beside the palette's Timer button, or closes it while it shows.
    private func showDelays(beside button: NSView) {
        toggleList(.timer, beside: button) {
            StudioTimerList(current: delay) { [weak self] delay in
                self?.listPanel.dismiss()
                self?.chooseDelay(delay)
            }
        }
    }

    // MARK: Clean background

    var background: StudioBackground { settings.settings.studioBackground }

    /// The Background list beside the palette's Background button, or closes it while it shows.
    private func showBackgrounds(beside button: NSView) {
        toggleList(.background, beside: button) {
            StudioBackgroundList(
                current: background,
                choose: { [weak self] background in
                    self?.listPanel.dismiss()
                    self?.chooseBackground(background)
                },
                chooseCustomColor: { [weak self] in
                    self?.listPanel.dismiss()
                    self?.chooseCustomColor()
                },
                chooseImage: { [weak self] in
                    self?.listPanel.dismiss()
                    self?.chooseBackgroundImage()
                },
                windowShadow: settings.settings.studioWindowShadow,
                toggleWindowShadow: { [weak self] in
                    self?.listPanel.dismiss()
                    self?.toggleWindowShadow()
                })
        }
    }

    func chooseBackground(_ background: StudioBackground) {
        settings.update { $0.studioBackground = background }
    }

    /// The system colour panel: each colour taken in it becomes the background. The app is
    /// activated first, since the panel hides while the app is inactive.
    func chooseCustomColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        if case .color(let color) = background {
            panel.color = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        }
        panel.setTarget(colorTarget)
        panel.setAction(#selector(ColorPanelTarget.colorChanged(_:)))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// An image file chosen in the open panel becomes the background. The sandbox lets the app read
    /// a chosen file only for now, so it is copied into the app's container, as references are,
    /// replacing the image chosen before.
    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageFileLoader.openableTypes
        panel.message = "Choose an image to lay under the studio's pictures."
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.useBackgroundImage(at: url) }
        }
    }

    private func useBackgroundImage(at url: URL) {
        Task {
            let largest = largestPicture
            guard let decoded = await Self.decodeBackground(at: url, largest: largest) else {
                let alert = NSAlert()
                alert.messageText = "The image couldn't be opened."
                alert.informativeText = url.lastPathComponent
                alert.runModal()
                return
            }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let fileName = "Background-\(UUID().uuidString).\(ext)"
            let manager = FileManager.default
            do {
                try manager.createDirectory(at: backgroundFolder, withIntermediateDirectories: true)
                try manager.copyItem(at: url, to: backgroundFolder.appending(path: fileName))
            } catch {
                // The image chosen before stays, and stays the background.
                log.error("Copying the background image failed: \(error.localizedDescription, privacy: .public)")
                return NSSound.beep()
            }
            // Only once the new copy is in place.
            for old in (try? manager.contentsOfDirectory(atPath: backgroundFolder.path)) ?? [] where old != fileName {
                try? manager.removeItem(at: backgroundFolder.appending(path: old))
            }
            backgroundImage = (fileName, largest, decoded.value)
            settings.update {
                $0.studioBackground = .image(BackgroundImage(fileName: fileName, name: url.lastPathComponent))
            }
        }
    }

    /// The largest picture any connected display allows, in pixels.
    private var largestPicture: PixelSize {
        StudioComposite.largestPicture(on: DisplayLayout.current()?.displays ?? [])
    }

    /// A background image, whole and upright, scaled down by ImageIO while it decodes to what still
    /// covers `largest` (`StudioComposite.backgroundMaxPixelSize`), so a large photo is neither cut
    /// to `ImageBudget` nor decoded at full size first. `nil` when ImageIO can't read it.
    @concurrent
    nonisolated private static func decodeBackground(
        at url: URL, largest: PixelSize
    ) async
        -> UncheckedSendable<CGImage>?
    {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = ImageOrientation(exif: properties[kCGImagePropertyOrientation] as? Int ?? 1)
        let upright =
            orientation.swapsSides ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: StudioComposite.backgroundMaxPixelSize(
                image: upright, display: largest),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map {
            UncheckedSendable(value: $0)
        }
    }

    struct BackgroundImageUnreadable: Error {}

    /// `background` ready to draw; `nil` for the screen.
    private func fill(for background: StudioBackground) async throws -> StudioFill? {
        switch background {
        case .screen: return nil
        case .color(let color): return .color(color)
        case .gradient(let gradient): return .gradient(gradient)
        case .image(let image):
            let largest = largestPicture
            if let backgroundImage, backgroundImage.fileName == image.fileName, backgroundImage.maxPixelSize == largest
            {
                return .image(backgroundImage.image)
            }
            guard
                let decoded = await Self.decodeBackground(
                    at: backgroundFolder.appending(path: image.fileName), largest: largest)
            else { throw BackgroundImageUnreadable() }
            backgroundImage = (image.fileName, largest, decoded.value)
            return .image(decoded.value)
        }
    }

    func toggleLeaveOutDock() {
        settings.update { $0.studioLeavesOutDock.toggle() }
    }

    func toggleLeaveOutDesktopIcons() {
        settings.update { $0.studioLeavesOutDesktopIcons.toggle() }
    }

    func togglePointer() {
        settings.update { $0.studioIncludesPointer.toggle() }
    }

    // MARK: Leaving out windows

    var isLeavingOutWindows: Bool { windowPicker != nil }
    var hasLeftOutWindows: Bool { !leftOutWindows.isEmpty }

    /// Starts pointing at windows to leave out, or ends it. While it runs, the window under the
    /// pointer is tinted, a click leaves it out or brings it back, and the palette floats above the
    /// picker so its button can end it; Escape ends it too.
    func toggleLeavingOutWindows() {
        if let windowPicker { return windowPicker.stop() }
        guard isVisible, let converter else { return }
        listPanel.dismiss()
        oneWindowPicker?.stop()
        advance(.pickerStarted)
        let picker = WindowPicker(
            windows: { ScreenWindows.windows(converter: converter) }, tint: SettingsColor.studio.nsColor,
            hint: { [weak self] window in
                self?.leftOutWindows.contains(window.id) == true
                    ? "Click to bring back · Esc to finish" : "Click to leave out · Esc to finish"
            },
            onClick: { [weak self] window in
                guard let self else { return }
                leftOutWindows = LeftOutWindows.toggled(window.id, in: leftOutWindows)
            },
            onFinish: { [weak self] in
                self?.windowPicker = nil
                self?.palette.isPickingWindows = false
            })
        windowPicker = picker
        palette.isPickingWindows = true
        picker.start()
    }

    func bringBackAllWindows() {
        leftOutWindows = []
    }

    /// Forgets the left-out windows that closed; a minimised or hidden one stays left out.
    private func dropClosedWindows() {
        guard !leftOutWindows.isEmpty, let existing = ScreenWindows.existingIDs() else { return }
        leftOutWindows = LeftOutWindows.keeping(leftOutWindows, existing: existing)
    }

    /// Dims the left-out windows inside the frame while the studio shows, and follows them ten
    /// times a second, forgetting closed ones once a second. Nothing runs while none is left out,
    /// nor while One Window has a window: its pictures leave nothing out.
    private func updateDimmed() {
        guard isVisible, !leftOutWindows.isEmpty, oneWindowMode.chosen == nil, let converter else {
            dimOverlay.orderOut(nil)
            dimTimer?.invalidate()
            dimTimer = nil
            return
        }
        let rect = frame.captureRect
        let scale = converter.owningDisplay(for: GlobalRect(rect: rect))?.scale ?? 1
        // The Viewer and the palette cover what is behind them; the frames and overlays don't.
        let own = Set([palette.windowNumber] + (viewerWindowNumber?().map { [$0] } ?? []))
        let rects = LeftOutWindows.dimmedRects(
            leftOutWindows, stack: ScreenWindows.stack(converter: converter, own: own), frame: rect, scale: scale)
        dimOverlay.show(rects, in: rect, below: frame.windowNumber)
        guard dimTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dimTicks += 1
                if self.dimTicks % 10 == 0 { self.dropClosedWindows() }
                self.updateDimmed()
            }
        }
        // Also while a menu is open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        dimTimer = timer
    }

    // MARK: One window

    /// Off, picking, or on for a window; for this session only, never saved.
    private(set) var oneWindowMode = OneWindowMode.off
    private var oneWindowPicker: WindowPicker?
    /// Looks once a second whether the chosen window closed, while one is chosen and the studio
    /// shows.
    private var oneWindowTimer: Timer?

    /// Starts picking the window for One Window, or ends picking, or lets the chosen window go.
    func toggleOneWindow() {
        send(.toggle(studioVisible: isVisible))
    }

    func toggleWindowShadow() {
        settings.update { $0.studioWindowShadow.toggle() }
    }

    /// Moves One Window on by `event` (`OneWindowMode.after`) and shows the result: the picker,
    /// the palette's button, the tab, and "Window gone" when the chosen window closed.
    private func send(_ event: OneWindowMode.Event) {
        let old = oneWindowMode
        let new = old.after(event)
        guard new != old else { return }
        oneWindowMode = new
        // Set first: stopping the picker reports a cancel, which then changes nothing.
        if old.isPicking { oneWindowPicker?.stop() }
        if new.isPicking { startOneWindowPicker() }
        if old.chosen != nil, new == .off, case .checked = event { frame.showNotice("Window gone") }
        palette.isPickingOneWindow = new.isPicking
        palette.hasOneWindow = new.chosen != nil
        frame.tabNote = new.tabNote
        updateOneWindowTimer()
        updateDimmed()
    }

    /// As Fit to Window does: the window under the pointer is tinted, a click chooses it, Escape
    /// or a click on no window cancels. The palette floats above the picker meanwhile, so its
    /// button cancels too.
    private func startOneWindowPicker() {
        windowPicker?.stop()
        advance(.pickerStarted)
        listPanel.dismiss()
        let picker = WindowPicker(
            windows: converter.map { ScreenWindows.windows(converter: $0) } ?? [], tint: SettingsColor.studio.nsColor,
            hint: "Click to capture this window alone · Esc to cancel"
        ) { [weak self] picked in
            guard let self else { return }
            oneWindowPicker = nil
            guard let picked else { return send(.cancelled) }
            let owner = ScreenWindows.owner(picked.id)
            send(.picked(OneWindowChoice(id: picked.id, appName: owner.name ?? "Window")))
            // The picker made this app active; the chosen window's app takes it back, so the window
            // is captured looking active.
            owner.pid.flatMap(NSRunningApplication.init(processIdentifier:))?.activate()
        }
        oneWindowPicker = picker
        picker.start()
    }

    /// Lets the chosen window go when it closed. A minimised or hidden one, or one on another
    /// Space, still exists and stays chosen.
    private func checkOneWindow() {
        guard oneWindowMode.chosen != nil, let existing = ScreenWindows.existingIDs() else { return }
        send(.checked(existing: existing))
    }

    private func updateOneWindowTimer() {
        guard isVisible, oneWindowMode.chosen != nil else {
            oneWindowTimer?.invalidate()
            oneWindowTimer = nil
            return
        }
        guard oneWindowTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkOneWindow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        oneWindowTimer = timer
    }

    // MARK: Displays

    /// Keeps the frame and the palette on a connected display.
    func screenParametersChanged() {
        frame.screenParametersChanged()
        if palette.isVisible, converter?.owningDisplay(for: GlobalRect(rect: palette.frame)) == nil {
            placePalette(besideFrame: true)
        }
    }

    private var converter: DisplayCoordinateConverter? {
        DisplayLayout.current().map(DisplayCoordinateConverter.init(layout:))
    }

    /// Where the palette was left, when that is still on a display; else beside the frame.
    private func placePalette(besideFrame: Bool = false) {
        guard let converter else { return }
        let size = palette.frame.size
        if !besideFrame, let saved = settings.settings.studioPaletteOrigin,
            converter.owningDisplay(for: GlobalRect(rect: CGRect(origin: saved, size: size))) != nil
        {
            palette.setFrameOrigin(saved)
            return
        }
        let area = frame.captureRect
        let display = converter.owningDisplay(for: GlobalRect(rect: area))
        let visible =
            display.flatMap { NSScreen.screen(forDisplay: $0.id) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? area
        palette.setFrameOrigin(StudioPlacement.paletteOrigin(size: size, beside: area, in: visible))
    }

    // MARK: Capture, Copy, Save

    /// Copies the frame's pixels to the clipboard, then asks where to save them.
    func capture() { press(.capture) }
    func copy() { press(.copy) }
    func save() { press(.save) }

    /// The countdown before a picture while a delay is set; the clock runs only while it counts.
    private var countdown = StudioCountdown.idle
    private var countdownTimer: Timer?
    private let countdownPanel = StudioCountdownPanel()
    /// Output as it was at the last press of Capture, Copy or Save: the picture it starts, now or
    /// when its countdown ends, is written so, whatever Output says meanwhile.
    private var pressedOutput = StudioOutput()
    /// Capture, Copy or Save pressed: `StudioCountdown.after` decides — cancel a running countdown,
    /// refuse now, take now, or count down, stopping a running window picker first.
    private func press(_ shot: StudioShot) {
        pressedOutput = settings.settings.studioOutput
        let pickerRunning = windowPicker != nil || oneWindowPicker != nil || frame.isPickingWindow
        advance(
            .press(
                shot, delay: delay, check: check, pickerRunning: pickerRunning,
                at: ProcessInfo.processInfo.systemUptime))
    }

    /// Moves the countdown on by `event` (`StudioCountdown.after`) and does what that says.
    private func advance(_ event: StudioCountdown.Event) {
        let (next, outcome) = countdown.after(event)
        countdown = next
        switch outcome {
        case .none: break
        case .shootNow(let shot), .refusedNow(let shot): take(shot)
        case .started(let stopsPicker):
            if stopsPicker {
                windowPicker?.stop()
                oneWindowPicker?.stop()
                frame.stopPickingWindow()
            }
            // 30 times a second for the ring, also while a menu is open or a window is dragged.
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            countdownTimer = timer
        case .cancelled, .frameOffDisplay, .fire:
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
        if outcome == .frameOffDisplay { frame.showNotice("Frame is not wholly on one display") }
        updateCountdownPanel()
        // Gone from the screen first; the filter leaves it out of the picture anyway.
        if case .fire(let shot) = outcome { take(shot) }
    }

    private func tick() {
        let onDisplay = converter?.owningDisplay(for: GlobalRect(rect: frame.captureRect)) != nil
        advance(.tick(at: ProcessInfo.processInfo.systemUptime, frameOnDisplay: onDisplay))
    }

    /// The countdown beside the frame's tab while it runs, following the frame; where the frame is
    /// on no display, the next tick stops it.
    private func updateCountdownPanel() {
        let now = ProcessInfo.processInfo.systemUptime
        guard countdown.isCounting, let tab = frame.tabArea,
            let screen = converter?.owningDisplay(for: GlobalRect(rect: frame.captureRect))?.globalFrame
        else { return countdownPanel.orderOut(nil) }
        let text = countdown.text(at: now)
        let rect = StudioCountdown.pillRect(size: countdownPanel.size(for: text), tab: tab, screen: screen)
        countdownPanel.show(
            text, seconds: countdown.secondsLeft(at: now), fraction: CGFloat(countdown.fractionLeft(at: now)),
            in: rect)
    }

    /// Whether a picture can be taken now (`StudioShotCheck`).
    private var check: StudioShotCheck {
        StudioShotCheck(
            visible: isVisible, capturing: isCapturing, savePanelOpen: savePanel?.isVisible == true,
            permitted: permissions.hasScreenRecordingAccess, onOneDisplay: frame.isWhollyOnOneDisplay)
    }

    /// Takes the picture, then writes it as Output said at the press, once for both the clipboard
    /// and the file, off the main actor: a large picture takes most of a second to encode.
    private func take(_ shot: StudioShot) {
        let output = pressedOutput
        take { [weak self] image, pointScale in
            let written = await Self.write(image, pointScale: pointScale, output: output, forPasteboard: shot != .save)
            guard let self, isVisible else { return }
            guard let written else { return NSSound.beep() }
            if shot != .save { copy(written) }
            if shot != .copy { save(written, as: output.format) }
        }
    }

    @concurrent
    private nonisolated static func write(
        _ image: CGImage, pointScale: CGFloat, output: StudioOutput, forPasteboard: Bool
    ) async -> StudioOutput.Written? {
        output.written(image, pointScale: pointScale, forPasteboard: forPasteboard)
    }

    private func copy(_ written: StudioOutput.Written) {
        ScreenshotExporter.copy(written.pasteboard)
        frame.showNotice("Copied \(written.picture.width) × \(written.picture.height) px")
    }

    /// The sandbox lets the app write only where the user picks, so saving goes through the save
    /// panel, opened in the screenshot folder with the file already named.
    private func save(_ written: StudioOutput.Written, as format: StudioOutput.Format) {
        NSApp.activate()
        let name = ScreenshotName.fileName(
            kind: "Screenshot", style: settings.settings.fileNameStyle,
            size: PixelSize(width: written.picture.width, height: written.picture.height),
            fileExtension: format.fileExtension)
        savePanel = export.saveImage(
            written.data, type: UTType(format.typeIdentifier) ?? .png, name: name, sheetOn: nil
        ) { [weak self] url in
            self?.frame.showNotice("Saved \(url.lastPathComponent)")
        }
    }

    /// Captures the frame's rect and hands the image on with its display's scale, unless the
    /// studio was hidden meanwhile.
    /// While a save panel is open, brings it forward instead: one panel at a time, and none in the
    /// picture.
    private func take(_ then: @escaping (CGImage, CGFloat) async -> Void) {
        switch check {
        case .ignore: return
        case .bringSavePanelForward:
            NSApp.activate()
            savePanel?.makeKeyAndOrderFront(nil)
            return
        case .needsPermission:
            onNeedsPermission?(false)
            return
        case .notOnOneDisplay:
            // A picture holds one display's pixels: a frame reaching onto another display, or off
            // every display, would give a smaller picture than the frame says.
            frame.showNotice("Frame is not wholly on one display")
            return
        case .take: break
        }
        guard let geometry = frame.captureGeometry else { return NSSound.beep() }
        isCapturing = true
        let included = capturedAppWindows?() ?? []
        let current = settings.settings
        let leaveOut = StudioLeaveOut(
            dock: current.studioLeavesOutDock, desktopIcons: current.studioLeavesOutDesktopIcons,
            background: current.studioBackground, windows: leftOutWindows)
        let chosen = oneWindowMode.chosen
        Task {
            defer { isCapturing = false }
            do {
                // With the screen as the background, a lone window has none: it stays transparent.
                let fill = try await fill(for: current.studioBackground)
                let image =
                    if let chosen {
                        try await StudioCapture.window(
                            chosen.id, frame: geometry.areaSize, display: geometry.display,
                            shadow: current.studioWindowShadow, over: fill)
                    } else {
                        try await StudioCapture.image(
                            of: geometry, including: included, leavingOut: leaveOut,
                            pointer: current.studioIncludesPointer, over: fill)
                    }
                if isVisible { await then(image, geometry.display.scale) }
            } catch  where ScreenCaptureManager.isPermissionError(error) {
                onNeedsPermission?(true)
            } catch let problem as StudioCapture.WindowProblem {
                switch problem {
                case .notListed:
                    // Closed, or minimised, hidden or on another Space.
                    checkOneWindow()
                    if oneWindowMode.chosen != nil { frame.showNotice("Window not on screen") }
                case .otherScale: frame.showNotice("Window on a display of another scale")
                case .largerThanFrame: frame.showNotice("Window larger than the frame")
                }
            } catch is BackgroundImageUnreadable {
                NSSound.beep()
                frame.showNotice("Background image can't be read")
            } catch {
                log.error("Studio capture failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
                frame.showNotice("Capture failed")
            }
        }
    }
}
