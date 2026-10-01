import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// The Screenshot studio: its frame, its palette, Capture,
/// Copy and Save, the frame's sizes and Aspect Lock, the timer, the background and its backdrop,
/// and One Window.
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
        palette.onSize = { [weak self] in self?.showSizes(from: $0) }
        palette.onFitToWindow = { [weak self] in self?.toggleFitToWindow() }
        palette.onToggleAspectLock = { [weak self] in self?.toggleAspectLock() }
        palette.onTimer = { [weak self] in
            guard let self, let menu = delayMenu?() else { return }
            palette.popUp(menu, from: $0)
        }
        palette.onOutput = { [weak self] in
            guard let self, let menu = outputMenu?() else { return }
            palette.popUp(menu, from: $0)
        }
        palette.onBackground = { [weak self] in self?.showBackgrounds(from: $0) }
        palette.onToggleOneWindow = { [weak self] in self?.toggleOneWindow() }
        palette.onOneWindowMenu = { [weak self] in self?.showOneWindowMenu() }
        palette.onHide = { [weak self] in self?.hide() }
        palette.studioFrame = { [weak self] in self?.frame.captureRect }
        palette.onMoved = { [weak self] in
            guard let self else { return }
            settings.update { $0.studioPaletteOrigin = self.palette.frame.origin }
        }
        // The frame's position box keeps off the palette, wherever it is moved, and One Window's
        // notice beside the palette follows it.
        paletteMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: palette, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePositionAvoiding()
                self?.placeOneWindowNotice()
            }
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

    /// Whether the studio shows: its palette, and its frame unless One Window hides it.
    private(set) var isVisible = false

    /// Shows the frame where it was, or centred on the main display the first time, unless One
    /// Window keeps a window chosen, and the palette where it was, or beside the frame.
    func show() {
        isVisible = true
        if oneWindowMode.usesFrame { frame.show() }
        if !palette.isVisible { placePalette() }
        palette.orderFrontRegardless()
        updatePositionAvoiding()
        updateOneWindowWatch()
        updateBackdrop()
    }

    /// Ends Fit to Window's picker too, or a pick would show the frame alone; One Window's ends
    /// with `.hidden`.
    func hide() {
        isVisible = false
        frame.stopPickingWindow()
        frame.hide()
        noticePanel.hide()
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

    /// The frame's size in pixels of its display, for the checkmark in the size menus.
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

    /// Screenshot › Size's menu, filled as it is now, which the palette's Size button pops up; set
    /// by the app.
    var sizeMenu: (() -> NSMenu?)?

    /// The Size menu from the palette, with a row to type a size in (`StudioSizeTypingItem`, a pilot)
    /// above Custom Size….
    private func showSizes(from button: PaletteButton) {
        guard let menu = sizeMenu?() else { return }
        if oneWindowMode.usesFrame,
            let index = menu.items.firstIndex(where: { $0.action == #selector(AppController.showStudioCustomSizes(_:)) }
            )
        {
            menu.insertItem(.separator(), at: index)
            menu.insertItem(StudioSizeTypingItem.make { [weak self] in self?.applySize($0) }, at: index)
        }
        palette.popUp(menu, from: button)
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
        // Shown while another app stays active: hiding on deactivation would hide it at once.
        window.hidesOnDeactivate = false
        return window
    }

    // MARK: Timer

    var delay: StudioDelay { settings.settings.studioDelay }

    func chooseDelay(_ delay: StudioDelay) {
        settings.update { $0.studioDelay = delay }
    }

    /// Screenshot › Delay's menu, which the palette's Timer button pops up; set by the app.
    var delayMenu: (() -> NSMenu?)?
    /// Screenshot › Output's menu, which the palette's Output button pops up; set by the app.
    var outputMenu: (() -> NSMenu?)?

    // MARK: Output

    /// Screenshot › Output, also as the palette's Output menu.
    func chooseFormat(_ format: StudioOutput.Format) {
        settings.update { $0.studioOutput.format = format }
    }

    func chooseColors(_ colors: StudioOutput.Colors) {
        settings.update { $0.studioOutput.colors = colors }
    }

    func chooseScale(_ scale: StudioOutput.Scale) {
        settings.update { $0.studioOutput.scale = scale }
    }

    // MARK: Background

    var background: StudioBackground { settings.settings.studioBackground }

    /// Screenshot › Background's menu with its colours and gradients as rows of swatches, which the
    /// palette's Background button pops up; set by the app.
    var backgroundMenu: ((@escaping MainMenu.SwatchRow) -> NSMenu?)?

    /// The Background menu from the palette: each section's swatches in one row
    /// (`StudioSwatchRow`), the current one ringed, greyed while One Window is on.
    private func showBackgrounds(from button: PaletteButton) {
        let current = background
        let isEnabled = oneWindowMode.usesFrame
        let row: MainMenu.SwatchRow = { [weak self] entries, header in
            StudioSwatchRow.view(entries: entries, current: current, isEnabled: isEnabled, header: header) {
                self?.chooseBackground($0)
            }
        }
        guard let menu = backgroundMenu?(row) else { return }
        palette.popUp(menu, from: button)
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

    /// The One Window menu's items' target, for as long as the menu may call it.
    private lazy var oneWindowMenu = StudioOneWindowMenu(
        mode: { [weak self] in self?.oneWindowMode ?? .off },
        windowShadow: { [weak self] in self?.settings.settings.studioWindowShadow ?? true },
        toggleWindowShadow: { [weak self] in self?.toggleWindowShadow() },
        pickAnother: { [weak self] in self?.send(.pickAnother) },
        end: { [weak self] in self?.send(.end) })

    /// The One Window menu beside the palette, made anew each time, so it reads the mode and the
    /// setting as they are.
    private func showOneWindowMenu() {
        palette.popUpOneWindowMenu(oneWindowMenu.makeMenu())
    }

    /// Moves One Window on by `event` (`OneWindowMode.after`) and shows the result: the picker,
    /// the palette's buttons, the chosen window's outline, and the frame, hidden while One Window
    /// is on and back where it was when it ends. Turning on closes the colour panel while it
    /// sets the background: Background is out of use, so a colour taken there would change it
    /// unseen.
    private func send(_ event: OneWindowMode.Event) {
        let old = oneWindowMode
        let new = old.after(event)
        guard new != old else { return }
        oneWindowMode = new
        // Set first: stopping the picker reports a cancel, which then changes nothing.
        if old.isPicking, !new.isPicking { oneWindowPicker?.stop() }
        if new.usesFrame != old.usesFrame {
            if new.usesFrame {
                noticePanel.hide()
                if isVisible { frame.show() }
            } else {
                if colorTarget.isActive { NSColorPanel.shared.close() }
                frame.stopPickingWindow()
                frame.hide()
            }
        }
        if new.isPicking, !old.isPicking { startOneWindowPicker() }
        palette.oneWindowMode = new
        updateOneWindowWatch()
    }

    /// The chosen window can't be captured any more (`problem`): One Window turns off, the frame
    /// comes back where it was, a running countdown stops, and no picture is taken. Quietly, unless
    /// the loss cancels something the user waits for — the countdown, or a capture they pressed
    /// (`pressed`), also one on its way whose window went meanwhile: then a beep and why, beside the
    /// frame's tab (`OneWindowProblem.notice`). While the studio is hidden, nothing is said.
    private func loseWindow(_ chosen: OneWindowChoice, _ problem: OneWindowProblem, pressed: Bool = false) {
        let cancels = pressed || countdown.isCounting
        if oneWindowMode.chosen == chosen {
            send(.unavailable(problem))
            advance(.windowLost)
        }
        if let text = problem.notice(cancels: cancels, studioVisible: isVisible) { beep(text) }
    }

    /// As Fit to Window does: the window under the pointer is tinted, a click chooses it, Escape
    /// or a click on no window cancels. The palette's button, above the picker, cancels too.
    private func startOneWindowPicker() {
        advance(.pickerStarted)
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
            MainActor.assumeIsolated {
                guard let self, let chosen = self.oneWindowMode.chosen else { return }
                self.loseWindow(chosen, .notListed)
            }
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
            placeOneWindowNotice()
        case .unsure: break
        case .unavailable: loseWindow(chosen, .notListed)
        }
    }

    /// Where One Window's notice or countdown of `size` goes while the frame is hidden
    /// (`StudioPlacement.oneWindowNotice`): beside the chosen window's name, or, while none shows,
    /// beside the palette level with its One Window button, kept on the palette's display. `nil`
    /// while neither shows.
    private func oneWindowNoticeRect(size: CGSize) -> CGRect? {
        if let place = oneWindowOutline.labelPlace {
            return StudioPlacement.oneWindowNotice(size: size, beside: place.label, in: place.screen)
        }
        guard palette.isVisible, let visible = palette.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        else { return nil }
        return StudioPlacement.oneWindowNotice(size: size, beside: palette.oneWindowRow, in: visible)
    }

    /// Moves One Window's notice, while it shows, after what it sits beside: the window's name,
    /// the palette, or the displays changed.
    private func placeOneWindowNotice() {
        guard let text = noticePanel.text, let rect = oneWindowNoticeRect(size: StudioNoticePanel.size(for: text))
        else { return }
        noticePanel.move(to: rect)
    }

    /// The display a picture of `chosen` is in: the one holding most of the window as now listed;
    /// `nil` when it isn't listed on screen.
    private func display(of chosen: OneWindowChoice) -> DisplayInfo? {
        guard let converter, let window = ScreenWindows.window(chosen.id, converter: converter) else { return nil }
        return converter.owningDisplay(for: GlobalRect(rect: window.frame))
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
        placeOneWindowNotice()
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
            let display = converter.owningDisplay(for: GlobalRect(rect: CGRect(origin: saved, size: size)))
        {
            let visible = NSScreen.screen(forDisplay: display.id)?.visibleFrame
            palette.setFrameOrigin(
                visible.map { StudioPlacement.restoredPaletteOrigin(saved, size: size, in: $0) } ?? saved)
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
    /// One Window's notices, while the frame beside whose tab they go is hidden.
    private let noticePanel = StudioNoticePanel()
    /// Output as it was at the last press of Capture, Copy or Save: the picture it starts, now or
    /// when its countdown ends, is written so, whatever Output says meanwhile.
    private var pressedOutput = StudioOutput()
    /// Capture, Copy or Save pressed: `StudioCountdown.after` decides — cancel a running countdown,
    /// refuse now, take now, or count down, stopping a running window picker first. A press that can take a picture now asks One Window first
    /// (`OneWindowMode.press`): during the first picking it is refused with "Pick a window first"
    /// and the picking goes on; during a re-pick the re-pick ends and the chosen window is taken.
    /// A press that is ignored, brings the save panel forward or stops a countdown leaves the mode
    /// as it is.
    private func press(_ shot: StudioShot) {
        let check = self.check
        if !countdown.isCounting, check == .take {
            if oneWindowMode.press == .pickFirst { return beep(OneWindowPress.pickFirstNotice) }
            send(.pressed)
        }
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
        if outcome == .frameOffDisplay { notice(Notice.notOnOneDisplay) }
        updateCountdownPanel()
        // Gone from the screen first; the filter leaves it out of the picture anyway.
        if case .fire(let shot) = outcome { take(shot) }
    }

    /// The frame's place matters only while it is in use: One Window's picture is the window's.
    private func tick() {
        let onDisplay =
            !oneWindowMode.usesFrame || converter?.owningDisplay(for: GlobalRect(rect: frame.captureRect)) != nil
        advance(.tick(at: ProcessInfo.processInfo.systemUptime, frameOnDisplay: onDisplay))
    }

    /// The countdown while it runs: beside the frame's tab, following the frame, or, while One
    /// Window hides the frame, beside the chosen window's name (`oneWindowNoticeRect`), following
    /// the window. Where the frame is on no display, the next tick stops it.
    private func updateCountdownPanel() {
        let now = ProcessInfo.processInfo.systemUptime
        guard countdown.isCounting else { return countdownPanel.orderOut(nil) }
        let text = countdown.text(at: now)
        let size = countdownPanel.size(for: text)
        let rect: CGRect?
        if oneWindowMode.usesFrame {
            rect = frame.tabArea.flatMap { tab in
                converter?.owningDisplay(for: GlobalRect(rect: frame.captureRect)).map {
                    StudioCountdown.pillRect(size: size, tab: tab, screen: $0.globalFrame)
                }
            }
        } else {
            rect = oneWindowNoticeRect(size: size)
        }
        guard let rect else { return countdownPanel.orderOut(nil) }
        countdownPanel.show(
            text, seconds: countdown.secondsLeft(at: now), fraction: CGFloat(countdown.fractionLeft(at: now)),
            in: rect)
    }

    /// Whether a picture can be taken now (`StudioShotCheck`). The frame's place matters only while
    /// it is in use.
    private var check: StudioShotCheck {
        StudioShotCheck(
            visible: isVisible, capturing: isCapturing, savePanelOpen: savePanel?.isVisible == true,
            permitted: permissions.hasScreenRecordingAccess,
            onOneDisplay: !oneWindowMode.usesFrame || frame.isWhollyOnOneDisplay)
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
        notice("Copied \(written.picture.width) × \(written.picture.height) px")
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
            self?.notice("Saved \(url.lastPathComponent)")
        }
    }

    /// Captures the frame's rect, or One Window's window alone, and hands the image on with its
    /// display's scale, unless the studio was hidden meanwhile: then the capture is dropped, its
    /// failure too, with no beep and no notice.
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
            notice(Notice.notOnOneDisplay)
            return
        case .take: break
        }
        isCapturing = true
        let included = (capturedAppWindows?() ?? []) + [backdrop.windowNumber]
        let shadow = settings.settings.studioWindowShadow
        let chosen = oneWindowMode.chosen
        Task {
            defer { isCapturing = false }
            do {
                if let chosen {
                    // Unavailable: One Window is off, and no picture is taken.
                    guard let window = try await windowPicture(chosen, shadow: shadow) else { return }
                    if isVisible { await then(window.image, window.scale) }
                    return
                }
                guard let geometry = frame.captureGeometry, let request = frame.screenshotRequest(for: geometry)
                else { return NSSound.beep() }
                // The backdrop is on screen: the picture is what the frame shows.
                await backdropOnScreen()
                let image = try await StudioCapture.image(request, on: geometry.display, including: included)
                if isVisible { await then(image, geometry.display.scale) }
            } catch {
                // Hidden meanwhile: the capture is cancelled, and nothing is said.
                guard isVisible else { return }
                if ScreenCaptureManager.isPermissionError(error) {
                    onNeedsPermission?(true)
                    return
                }
                log.error("Studio capture failed: \(error.localizedDescription, privacy: .public)")
                beep(Notice.captureFailed)
            }
        }
    }

    /// The notices said from more than one place.
    private enum Notice {
        static let notOnOneDisplay = "Frame is not wholly on one display"
        static let backgroundUnreadable = "Background image can't be read"
        static let captureFailed = "Capture failed"
    }

    /// A failure: a beep, and `text` as a notice.
    private func beep(_ text: String) {
        NSSound.beep()
        notice(text)
    }

    /// Shows `text` for a moment: beside the frame's tab, or, while One Window hides the frame,
    /// beside the chosen window's name or the palette (`oneWindowNoticeRect`).
    private func notice(_ text: String) {
        guard !oneWindowMode.usesFrame else { return frame.showNotice(text) }
        guard let rect = oneWindowNoticeRect(size: StudioNoticePanel.size(for: text)) else { return }
        noticePanel.show(text, in: rect)
    }

    /// One Window's picture of `chosen` (`StudioCapture.window`) with its display's scale, or `nil`
    /// when the window turns out unavailable (`OneWindowPicture.shot`): One Window turns off, the
    /// frame shows again, and no picture is taken (`loseWindow`).
    private func windowPicture(
        _ chosen: OneWindowChoice, shadow: Bool
    ) async throws -> (image: CGImage, scale: CGFloat)? {
        do {
            guard let display = display(of: chosen) else { throw OneWindowProblem.notListed }
            return (try await StudioCapture.window(chosen.id, display: display, shadow: shadow), display.scale)
        } catch let problem as OneWindowProblem {
            loseWindow(chosen, problem, pressed: true)
            return nil
        }
    }
}
