import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// The Screenshot studio (docs/product.md, Screenshot studio): its frame, its palette, Capture,
/// Copy and Save, the frame's sizes and Aspect Lock, the timer, the background and its backdrop,
/// the pointer, and One Window.
/// Shown and hidden on its own, apart from the Viewer and the Capture Area.
///
/// The frame is an `OverlayFrameController` of kind `.studio`: the Capture Area's window, drawing,
/// dragging and snapping, without its locks. The palette is a separate panel, parked anywhere.
@MainActor
final class StudioController {
    /// Called when a capture needs Screen Recording access: the Viewer explains and asks for it.
    /// `deniedByCapture`: ScreenCaptureKit refused although the preflight check said yes.
    var onNeedsPermission: ((_ deniedByCapture: Bool) -> Void)?
    /// The numbers of the app's windows a picture keeps — the Viewer and the Capture Area frame —
    /// besides the backdrop; every other window of the app is left out.
    var capturedAppWindows: (() -> [Int])?
    /// Called with the backdrop's window number when it shows, and with `nil` when it hides: the
    /// Viewer's stream keeps it.
    var onBackdropChange: ((CGWindowID?) -> Void)?

    private let frame: OverlayFrameController
    private let palette = StudioPalette()
    private let settings: SettingsStore
    private let permissions: PermissionsManager
    private let export: ExportController
    private let log = Logger(category: "studio")
    /// A capture is on its way; presses meanwhile are ignored.
    private var isCapturing = false
    /// The last save panel; while it is open, the commands bring it forward instead.
    private var savePanel: NSSavePanel?
    /// The Size, the Timer or the Background list beside the palette; the palette knows whose it is.
    private let listPanel = StudioListPanel()
    /// Built the first time Custom Size… is chosen, then kept.
    private var customSizesWindow: NSPanel?
    private let colorTarget = ColorPanelTarget()
    private var paletteMoveObserver: NSObjectProtocol?
    private var colorSpaceObserver: NSObjectProtocol?
    private let backdrop = StudioBackdropWindow()
    /// The decoded background image, by its file name.
    private var backgroundImage: (fileName: String, maxPixelSize: PixelSize, image: CGImage)?
    /// Where the chosen background image is copied, in the app's container.
    private let backgroundFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.bundleIdentifier ?? "Screen Loupe").appending(path: "Studio")

    init(settings: SettingsStore, permissions: PermissionsManager, export: ExportController) {
        self.settings = settings
        self.permissions = permissions
        self.export = export
        frame = OverlayFrameController(settings: settings, kind: .studio) {
            StudioPlacement.defaultFrame(in: $0, paletteWidth: StudioPalette.width)
        }
        frame.onPickWindow = { [weak self] in self?.toggleFitToWindow() }
        // The palette's Fit to Window button shows pressed while the frame's picker runs.
        frame.onPickerStarted = { [weak self] in self?.palette.isPickingWindow = true }
        frame.onPickerEnded = { [weak self] in self?.palette.isPickingWindow = false }
        palette.onCapture = { [weak self] in self?.capture() }
        palette.onCopy = { [weak self] in self?.copy() }
        palette.onSave = { [weak self] in self?.save() }
        palette.onSize = { [weak self] in self?.showSizes(beside: $0) }
        palette.onFitToWindow = { [weak self] in self?.toggleFitToWindow() }
        palette.onToggleAspectLock = { [weak self] in self?.toggleAspectLock() }
        palette.onTimer = { [weak self] in self?.showDelays(beside: $0) }
        palette.onBackground = { [weak self] in self?.showBackgrounds(beside: $0) }
        palette.onToggleOneWindow = { [weak self] in self?.toggleOneWindow() }
        palette.onTogglePointer = { [weak self] in self?.togglePointer() }
        palette.onHide = { [weak self] in self?.hide() }
        palette.onDragStarted = { [weak self] in self?.listPanel.dismiss() }
        listPanel.onClose = { [weak self] in self?.palette.openListButton = nil }
        palette.studioFrame = { [weak self] in self?.frame.captureRect }
        palette.onMoved = { [weak self] in
            guard let self else { return }
            settings.update { $0.studioPaletteOrigin = self.palette.frame.origin }
        }
        // The frame's position box keeps off the palette, wherever it is moved.
        paletteMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: palette, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePositionAvoiding() }
        }
        settings.observe(\.studioAspectLocked) { [weak self] in self?.palette.aspectLocked = $0 }
        settings.observe(\.activeStudioAspectRatio) { [weak self] in self?.frame.aspectRatio = $0.map { CGFloat($0) } }
        settings.observe(\.studioBackground) { [weak self] in
            self?.palette.hasBackground = $0 != .screen
            // The decoded image isn't kept for a background that no longer is one.
            if case .image = $0 {} else { self?.backgroundImage = nil }
            self?.updateBackdrop()
        }
        // The backdrop is drawn in its display's colour space.
        colorSpaceObserver = NotificationCenter.default.addObserver(
            forName: NSScreen.colorSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBackdrop() }
        }
        settings.observe(\.studioDelay) { [weak self] in self?.palette.hasDelay = $0 != .off }
        settings.observe(\.studioIncludesPointer) { [weak self] in self?.palette.includesPointer = $0 }
        // The countdown moves with the frame, and the backdrop goes with it to another display.
        frame.onChange = { [weak self] in
            self?.updateCountdownPanel()
            self?.updateBackdrop()
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
        updatePositionAvoiding()
        updateOneWindowWatch()
        updateBackdrop()
    }

    /// Ends Fit to Window's picker too, or a pick would show the frame alone; One Window's ends
    /// with `.hidden`.
    func hide() {
        listPanel.dismiss()
        frame.stopPickingWindow()
        frame.hide()
        palette.orderOut(nil)
        updatePositionAvoiding()
        advance(.hidden)
        send(.hidden)
        updateOneWindowWatch()
        updateBackdrop()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func updatePositionAvoiding() {
        frame.positionAvoiding = palette.isVisible ? palette.frame : .null
    }

    // MARK: Sizes

    /// The frame's size in pixels of its display, for the checkmark in the size lists.
    var pixelSize: PixelSize? { frame.pixelSize }

    /// Gives the frame `size` pixels (`OverlayFrameController.resize(toPixels:)`), unless its display
    /// can't hold them. With Aspect Lock on, the lock takes the frame's ratio.
    func applySize(_ size: PixelSize) {
        guard isVisible else { return }
        if frame.resize(toPixels: size) { retakeAspectRatio() }
    }

    /// Fit to Window, from the frame's tab, the palette or the Screenshot menu: starts the window
    /// picker, and a click on a window fits the frame to it; while the picker runs, cancels it.
    /// Starting it is a picker start, which stops a countdown.
    func toggleFitToWindow() {
        if frame.isPickingWindow { return frame.stopPickingWindow() }
        advance(.pickerStarted)
        listPanel.dismiss()
        // A window picked with Aspect Lock on gives the lock its ratio, as a size does.
        frame.pickWindow { [weak self] in self?.retakeAspectRatio() }
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
        toggleList(beside: button) {
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
    /// that button's list; another list in it is replaced.
    private func toggleList<List: View>(beside button: NSView, _ list: () -> List) {
        if palette.openListButton === button {
            listPanel.dismiss()
            return
        }
        listPanel.dismiss()
        let paletteFrame = palette.frame
        let anchorTop = palette.convertToScreen(button.convert(button.bounds, to: nil)).maxY
        let visible = palette.screen?.visibleFrame ?? paletteFrame
        listPanel.show(list(), beside: palette) {
            StudioPlacement.popoverOrigin(size: $0, beside: paletteFrame, anchorTop: anchorTop, in: visible)
        }
        palette.openListButton = button
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
        toggleList(beside: button) {
            StudioTimerList(current: delay) { [weak self] delay in
                self?.listPanel.dismiss()
                self?.chooseDelay(delay)
            }
        }
    }

    // MARK: Background

    var background: StudioBackground { settings.settings.studioBackground }

    /// The Background list beside the palette's Background button, or closes it while it shows.
    private func showBackgrounds(beside button: NSView) {
        toggleList(beside: button) {
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

    /// The system colour panel: each colour taken in it becomes the background, until the panel
    /// closes or a colour well in Settings takes it (`ColorPanelTarget`). The app is activated
    /// first, since the panel hides while the app is inactive.
    func chooseCustomColor() {
        NSColorPanel.shared.showsAlpha = false
        var current: NSColor?
        if case .color(let color) = background {
            current = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        }
        NSApp.activate()
        colorTarget.show(from: current)
    }

    /// An image file chosen in the open panel becomes the background. The sandbox lets the app read
    /// a chosen file only for now, so it is copied into the app's container, as references are,
    /// replacing the image chosen before.
    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageFileLoader.openableTypes
        panel.message = "Choose an image to show behind your windows."
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.useBackgroundImage(at: url) }
        }
    }

    /// Counts the images chosen: one chosen later wins, even when an earlier one finishes after it.
    private var backgroundRequest = 0

    private func useBackgroundImage(at url: URL) {
        backgroundRequest += 1
        let request = backgroundRequest
        Task {
            let largest = largestPicture
            let decoded = await Self.decodeBackground(at: url, largest: largest)
            guard request == backgroundRequest else { return }
            guard let decoded else {
                let alert = NSAlert()
                alert.messageText = "The image couldn't be opened."
                alert.informativeText = url.lastPathComponent
                alert.runModal()
                return
            }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let fileName = "Background-\(UUID().uuidString).\(ext)"
            let copy = backgroundFolder.appending(path: fileName)
            let copyError = await Self.copy(url, to: copy)
            let manager = FileManager.default
            guard request == backgroundRequest else {
                try? manager.removeItem(at: copy)
                return
            }
            if let copyError {
                // The image chosen before stays, and stays the background.
                log.error("Copying the background image failed: \(copyError.localizedDescription, privacy: .public)")
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

    /// Copies `url` to `copy`, making its folder, off the main actor: a large photo takes a moment.
    /// The error, if it failed.
    @concurrent
    nonisolated private static func copy(_ url: URL, to copy: URL) async -> (any Error)? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: url, to: copy)
            return nil
        } catch {
            return error
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
            // Kept only while it is still the background.
            if self.background == background { backgroundImage = (image.fileName, largest, decoded.value) }
            return .image(decoded.value)
        }
    }

    // MARK: Backdrop

    /// What the backdrop shows and what was asked for (`StudioBackdrop.Tracker`).
    private var backdropTracker = StudioBackdrop.Tracker()
    /// The latest backdrop drawing, until a picture has waited for it (`backdropOnScreen`).
    private var backdropRender: Task<Void, Never>?

    /// Shows the backdrop on the frame's display while the studio shows and a background other
    /// than the screen is chosen (`StudioBackdrop.placement`), hides it otherwise; when a picture
    /// is drawn and which one shows, `StudioBackdrop.Tracker` decides. Moving the frame within its
    /// display does nothing.
    private func updateBackdrop() {
        let wanted = StudioBackdrop.placement(
            studioVisible: isVisible, background: background, frame: GlobalRect(rect: frame.captureRect),
            converter: converter
        ).map { StudioBackdrop.Target(placement: $0, space: NSScreen.colorSpace(forDisplay: $0.display.id)) }
        switch backdropTracker.update(wanted: wanted) {
        case .none: return
        case .hide: hideBackdrop()
        case .render(let target, let request, let hidesFirst):
            if hidesFirst { hideBackdrop() }
            render(target, request: request)
        }
    }

    private func render(_ target: StudioBackdrop.Target, request: Int) {
        let wanted = target.placement
        backdropRender = Task {
            var image: CGImage?
            var unreadable = false
            do {
                if let fill = try await fill(for: wanted.background) {
                    image = await Self.drawBackdrop(fill, size: wanted.pixelSize, space: target.space)
                }
            } catch {
                unreadable = true
            }
            switch backdropTracker.finished(request, drawn: image != nil) {
            case .stale: return
            case .failed(let hides):
                if hides { hideBackdrop() }
                if unreadable {
                    beep(Notice.backgroundUnreadable)
                } else {
                    log.error("The backdrop couldn't be drawn.")
                }
            case .shown(let announces):
                // `.shown` comes only with a picture.
                guard let image else { return }
                backdrop.show(image, over: wanted.display.globalFrame)
                if announces { onBackdropChange?(CGWindowID(backdrop.windowNumber)) }
            }
        }
    }

    /// Hides the backdrop's window; the tracker has already taken it as hidden.
    private func hideBackdrop() {
        backdrop.hide()
        onBackdropChange?(nil)
    }

    /// Waits until the backdrop the studio last asked for is on screen, so a picture taken right
    /// after a background is chosen, or the frame moved to another display, doesn't catch the
    /// wallpaper or the old background while the new one is drawn (about 0.1 s). After any drawing
    /// since the last picture: waits for it to finish, commits the window's layer at once, and lets
    /// the display refresh twice, so the window server has composited it. With no drawing since,
    /// returns at once.
    private func backdropOnScreen() async {
        var drew = false
        while let render = backdropRender {
            await render.value
            drew = true
            // A newer drawing may have started meanwhile: the loop waits for that one too.
            if backdropRender == render { backdropRender = nil }
        }
        guard drew else { return }
        CATransaction.flush()
        if let screen = backdrop.screen ?? NSScreen.main { await ScreenRefresh.wait(2, on: screen) }
    }

    /// `StudioComposite.filled`, off the main actor: a whole display over an image takes a while.
    @concurrent
    private nonisolated static func drawBackdrop(
        _ fill: StudioFill, size: PixelSize, space: CGColorSpace
    ) async -> CGImage? {
        StudioComposite.filled(fill, size: size, space: space)
    }

    func togglePointer() {
        settings.update { $0.studioIncludesPointer.toggle() }
    }

    /// Another window picker of the app opened, which ended any of the studio's: a countdown stops.
    func windowPickerStarted() {
        advance(.pickerStarted)
    }

    // MARK: One window

    /// Off, picking, or on for a window; for this session only, never saved.
    private(set) var oneWindowMode = OneWindowMode.off
    private var oneWindowPicker: WindowPicker?
    /// The chosen window's outline, while one is chosen and the studio shows.
    private let oneWindowOutline = OneWindowOutlinePanel()
    private var oneWindowWatch = OneWindowWatch()
    /// Reads the chosen window's place every `WindowMagnet.readInterval`, while one is chosen and
    /// the studio shows, and only then.
    private var oneWindowTimer: Timer?
    private var oneWindowSpaceObserver: NSObjectProtocol?
    /// The displays as they were when the reads started, or at their last change.
    private var oneWindowConverter: DisplayCoordinateConverter?

    /// Starts picking the window for One Window, or ends picking, or lets the chosen window go.
    func toggleOneWindow() {
        send(.toggle(studioVisible: isVisible))
    }

    func toggleWindowShadow() {
        settings.update { $0.studioWindowShadow.toggle() }
    }

    /// Moves One Window on by `event` (`OneWindowMode.after`) and shows the result: the picker,
    /// the palette's button and the chosen window's outline.
    private func send(_ event: OneWindowMode.Event) {
        let old = oneWindowMode
        let new = old.after(event)
        guard new != old else { return }
        oneWindowMode = new
        // Set first: stopping the picker reports a cancel, which then changes nothing.
        if old.isPicking { oneWindowPicker?.stop() }
        if new.isPicking { startOneWindowPicker() }
        palette.isPickingOneWindow = new.isPicking
        palette.hasOneWindow = new.chosen != nil
        updateOneWindowWatch()
    }

    /// As Fit to Window does: the window under the pointer is tinted, a click chooses it, Escape
    /// or a click on no window cancels. The palette's button, above the picker, cancels too.
    private func startOneWindowPicker() {
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
            // The chosen window's app becomes the active one, so the window is captured looking active.
            // It takes that from the app active now: another app when picking started from the
            // palette, this one after the Screenshot menu; a plain `activate()` is refused in the
            // first case.
            if let app = owner.pid.flatMap(NSRunningApplication.init(processIdentifier:)) {
                NSApp.yieldActivation(to: app)
                app.activate(from: NSWorkspace.shared.frontmostApplication ?? .current, options: [])
            }
        }
        oneWindowPicker = picker
        picker.start()
    }

    /// Reads the chosen window's place while one is chosen and the studio shows: the outline
    /// follows it, and One Window turns off once it is unavailable (`OneWindowWatch`), or at a
    /// change of Space — the user leaving for another one, or the window going full screen. Stops
    /// reading and hides the outline otherwise.
    private func updateOneWindowWatch() {
        guard isVisible, oneWindowMode.chosen != nil else {
            oneWindowTimer?.invalidate()
            oneWindowTimer = nil
            oneWindowSpaceObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
            oneWindowSpaceObserver = nil
            oneWindowConverter = nil
            oneWindowOutline.hide()
            return
        }
        guard oneWindowTimer == nil else { return }
        oneWindowWatch = OneWindowWatch()
        oneWindowConverter = converter
        let timer = Timer(timeInterval: WindowMagnet.readInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readOneWindow() }
        }
        // Also while a menu is open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        oneWindowTimer = timer
        oneWindowSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(.unavailable) }
        }
        readOneWindow()
    }

    private func readOneWindow() {
        guard let chosen = oneWindowMode.chosen, let converter = oneWindowConverter else { return }
        switch oneWindowWatch.read(ScreenWindows.window(chosen.id, converter: converter)) {
        case .shows(let window):
            let display = converter.owningDisplay(for: GlobalRect(rect: window))
            let screen = display.flatMap { NSScreen.screen(forDisplay: $0.id) }?.visibleFrame ?? window
            oneWindowOutline.show(
                around: window, appName: chosen.appName, lineWidth: CGFloat(settings.settings.frameLineWidth),
                screen: screen)
        case .unsure: break
        case .unavailable: send(.unavailable)
        }
    }

    // MARK: Displays

    /// Keeps the frame and the palette on a connected display, and the backdrop over the frame's
    /// display as it now is.
    func screenParametersChanged() {
        frame.screenParametersChanged()
        if oneWindowConverter != nil { oneWindowConverter = converter }
        if palette.isVisible, converter?.owningDisplay(for: GlobalRect(rect: palette.frame)) == nil {
            placePalette(besideFrame: true)
        }
        updateBackdrop()
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
    /// refuse now, take now, or count down, stopping a running window picker first. Any press
    /// closes an open list.
    private func press(_ shot: StudioShot) {
        listPanel.dismiss()
        pressedOutput = settings.settings.studioOutput
        let pickerRunning = oneWindowPicker != nil || frame.isPickingWindow
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
        if outcome == .frameOffDisplay { frame.showNotice(Notice.notOnOneDisplay) }
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
            guard let written else { return beep(Notice.captureFailed) }
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
            frame.showNotice(Notice.notOnOneDisplay)
            return
        case .take: break
        }
        guard let geometry = frame.captureGeometry else { return NSSound.beep() }
        isCapturing = true
        let included = (capturedAppWindows?() ?? []) + [backdrop.windowNumber]
        let current = settings.settings
        let chosen = oneWindowMode.chosen
        Task {
            defer { isCapturing = false }
            do {
                let image: CGImage
                if let chosen, let window = try await windowPicture(chosen, geometry: geometry, settings: current) {
                    image = window
                } else {
                    // The backdrop is on screen: the picture is what the frame shows.
                    await backdropOnScreen()
                    image = try await StudioCapture.image(
                        of: geometry, including: included, pointer: current.studioIncludesPointer)
                }
                if isVisible { await then(image, geometry.display.scale) }
            } catch  where ScreenCaptureManager.isPermissionError(error) {
                onNeedsPermission?(true)
            } catch is BackgroundImageUnreadable {
                beep(Notice.backgroundUnreadable)
            } catch {
                log.error("Studio capture failed: \(error.localizedDescription, privacy: .public)")
                beep(Notice.captureFailed)
            }
        }
    }

    /// The notices beside the frame's tab said from more than one place.
    private enum Notice {
        static let notOnOneDisplay = "Frame is not wholly on one display"
        static let backgroundUnreadable = "Background image can't be read"
        static let captureFailed = "Capture failed"
    }

    /// A failure: a beep, and `notice` beside the frame's tab.
    private func beep(_ notice: String) {
        NSSound.beep()
        frame.showNotice(notice)
    }

    /// One Window's picture of `chosen` (`StudioCapture.window`), or `nil` when the window turns out
    /// unavailable (`OneWindowPicture.shot`): One Window turns off, and the press takes the frame's
    /// picture instead.
    private func windowPicture(
        _ chosen: OneWindowChoice, geometry: CaptureGeometry, settings current: Settings
    ) async throws -> CGImage? {
        do {
            // With the screen as the background, a lone window has none: it stays transparent.
            let fill = try await fill(for: current.studioBackground)
            return try await StudioCapture.window(
                chosen.id, frame: geometry.areaSize, display: geometry.display, shadow: current.studioWindowShadow,
                over: fill)
        } catch is OneWindowProblem {
            if oneWindowMode.chosen == chosen { send(.unavailable) }
            return nil
        }
    }
}
