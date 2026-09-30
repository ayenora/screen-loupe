import AppKit
import CoreVideo

/// The pixel being inspected and the Color Meter's kept colours.
///
/// The inspected pixel is the one under the mouse in the Viewer; when the mouse is elsewhere, the
/// one under the real cursor inside the Capture Area. Its colour is read straight from the latest
/// frame, so it is exactly what the Viewer shows.
@MainActor
final class PixelInspector {
    enum Source: Equatable {
        case viewer
        case captureArea
    }

    struct Probe: Equatable {
        var source: Source
        /// Capture Area pixel, from its top-left corner.
        var x: Int
        var y: Int
        /// `nil` when the pixel isn't in the captured image (the part of a straddling area that lies
        /// on the other display).
        var sample: ColorSample?
    }

    private(set) var probe: Probe?
    /// Recent, the favourites and the contrast pair, with the focus and the target.
    private(set) var colors: ColorMeterState
    var onChange: (() -> Void)?

    private let frameStore: FrameStore
    private let settings: SettingsStore
    private var viewerPixel: (x: Int, y: Int)?
    private var areaPixel: (x: Int, y: Int)?

    init(frameStore: FrameStore, settings: SettingsStore) {
        self.frameStore = frameStore
        self.settings = settings
        colors = ColorMeterState(recent: settings.settings.pinnedColors, saved: settings.settings.meterColors)
    }

    // MARK: Pointing

    func setViewerPixel(_ pixel: (x: Int, y: Int)?) {
        viewerPixel = pixel
        // Pointing into the image brings the live pixel back into focus; a new frame under a
        // pointer that didn't move doesn't.
        update(focusChanged: pixel != nil && colors.pointerMovedOverImage())
    }

    /// `pointerMoved`: the real cursor moved, which brings the live pixel back into focus as in the
    /// Viewer; the area moving or a new frame under a still cursor doesn't.
    func setAreaPixel(_ pixel: (x: Int, y: Int)?, pointerMoved: Bool = false) {
        areaPixel = pixel
        update(focusChanged: pointerMoved && pixel != nil && colors.pointerMovedOverImage())
    }

    /// A new frame: the colour under a pointer that didn't move may still have changed.
    func frameArrived() {
        guard probe != nil else { return }
        update()
    }

    private func update(focusChanged: Bool = false) {
        let next: Probe?
        if let pixel = viewerPixel {
            next = Probe(source: .viewer, x: pixel.x, y: pixel.y, sample: sample(atAreaPixel: pixel))
        } else if let pixel = areaPixel {
            next = Probe(source: .captureArea, x: pixel.x, y: pixel.y, sample: sample(atAreaPixel: pixel))
        } else {
            next = nil
        }
        guard next != probe || focusChanged else { return }
        probe = next
        onChange?()
    }

    /// The colour of a Capture Area pixel in the frame the Viewer shows.
    private func sample(atAreaPixel pixel: (x: Int, y: Int)) -> ColorSample? {
        guard let frame = frameStore.shownFrame else { return nil }
        let x = pixel.x - Int(frame.layout.imageOrigin.x)
        let y = pixel.y - Int(frame.layout.imageOrigin.y)
        let size = frame.pixelSize
        guard x >= 0, y >= 0, x < size.width, y < size.height else { return nil }

        let buffer = frame.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytes = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        // 32BGRA, in the frame's colour space: its display's, or the one kept with it; an opened
        // image's straight alpha is its own too.
        return ColorSample(
            red: bytes[2], green: bytes[1], blue: bytes[0], alpha: frame.hasAlpha ? bytes[3] : 255,
            colorSpace: frame.colorSpace, spaceName: frame.colorSpaceName)
    }

    // MARK: Kept colours

    /// Picks the inspected colour (`ColorMeterState.pick`); returns it, or `nil` when there is
    /// nothing to pick.
    @discardableResult
    func pickProbe() -> PickedColor? {
        guard let probe, let sample = probe.sample else { return nil }
        let color = PickedColor(sample, x: probe.x, y: probe.y)
        changeColors { $0.pick(color) }
        return color
    }

    /// Changes the kept colours, saves them and tells the panel.
    @discardableResult
    func changeColors<Result>(_ change: (inout ColorMeterState) -> Result) -> Result {
        let result = change(&colors)
        settings.update {
            $0.pinnedColors = colors.recent
            $0.meterColors = colors.saved
        }
        onChange?()
        return result
    }
}
