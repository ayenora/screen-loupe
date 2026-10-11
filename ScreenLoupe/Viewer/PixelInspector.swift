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
        /// The square of pixels `sample` was read from, when `reader` gave one; outlined in the Viewer
        /// and kept with a picked colour.
        var square: SampleSquare?

        /// The colour as a click keeps it.
        var picked: PickedColor? {
            guard var color = sample.map({ PickedColor($0, x: x, y: y) }) else { return nil }
            color.sampleSide = square?.side
            return color
        }
    }

    /// A square of pixels around the one pointed at, that a reading came from.
    struct SampleSquare: Equatable {
        /// Its side in pixels.
        var side: Int
        /// The pixels it covers: Capture Area pixels in a probe, the frame's in a `reader`'s result.
        var rect: PixelRect
    }

    /// When set, gives the colour at `x`, `y`, a pixel of the frame, with the square of pixels it
    /// came from, in place of reading that pixel; `nil` from it, or no reader, reads the pixel.
    var reader: ((_ pixels: FramePixels, _ x: Int, _ y: Int) -> (sample: ColorSample, square: SampleSquare)?)?

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

    /// Reads the pixel pointed at again, as after a new frame.
    func readAgain() {
        update()
    }

    private func update(focusChanged: Bool = false) {
        let next: Probe?
        if let pixel = viewerPixel {
            next = probe(.viewer, atAreaPixel: pixel)
        } else if let pixel = areaPixel {
            next = probe(.captureArea, atAreaPixel: pixel)
        } else {
            next = nil
        }
        guard next != probe || focusChanged else { return }
        probe = next
        onChange?()
    }

    /// The colour of a Capture Area pixel in the frame the Viewer shows.
    private func probe(_ source: Source, atAreaPixel pixel: (x: Int, y: Int)) -> Probe {
        let probe = Probe(source: source, x: pixel.x, y: pixel.y)
        guard let frame = frameStore.shownFrame else { return probe }
        let origin = (x: Int(frame.layout.imageOrigin.x), y: Int(frame.layout.imageOrigin.y))
        let x = pixel.x - origin.x
        let y = pixel.y - origin.y
        let size = frame.pixelSize
        guard x >= 0, y >= 0, x < size.width, y < size.height else { return probe }

        let colorSpace = frame.colorSpace
        let spaceName = frame.colorSpaceName
        let read: Probe? = frame.withPixels { base, bytesPerRow, _ in
            var probe = probe
            // 32BGRA, in the frame's colour space: its display's, or the one kept with it; an opened
            // image's straight alpha is its own too.
            let pixels = FramePixels(
                width: size.width, height: size.height, colorSpace: colorSpace, spaceName: spaceName,
                hasAlpha: frame.hasAlpha, base: base, bytesPerRow: bytesPerRow)
            if let reading = reader?(pixels, x, y) {
                probe.sample = reading.sample
                var square = reading.square
                square.rect.x += origin.x
                square.rect.y += origin.y
                probe.square = square
            } else {
                probe.sample = pixels.sample(x: x, y: y)
            }
            return probe
        }
        return read ?? probe
    }

    // MARK: Kept colours

    /// Picks the inspected colour (`ColorMeterState.pick`); returns it, or `nil` when there is
    /// nothing to pick.
    @discardableResult
    func pickProbe() -> PickedColor? {
        guard let color = probe?.picked else { return nil }
        changeColors { $0.pick(color) }
        return color
    }

    /// Picks the colour of a Capture Area pixel in the frame the Viewer shows, read as the inspected
    /// one is and kept as a click keeps it (`ColorMeterState.pick`); returns it, or `nil` when the
    /// pixel isn't in the frame.
    func pick(atAreaPixel pixel: (x: Int, y: Int)) -> PickedColor? {
        guard let color = probe(.captureArea, atAreaPixel: pixel).picked else { return nil }
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

/// A frame's pixels while the inspector reads them: 32-bit BGRA with straight alpha, in the frame's
/// colour space. Valid only during the call it is passed to.
struct FramePixels {
    let width: Int
    let height: Int
    let colorSpace: CGColorSpace
    /// The name the Color Meter shows for `colorSpace`, if it has one of its own.
    let spaceName: String?
    let hasAlpha: Bool
    fileprivate let base: UnsafeRawPointer
    fileprivate let bytesPerRow: Int

    /// The components of a pixel inside the frame; alpha is 255 in a frame without one.
    func rgba(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let bytes = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
        return (bytes[2], bytes[1], bytes[0], hasAlpha ? bytes[3] : 255)
    }

    /// The colour of one pixel inside the frame.
    func sample(x: Int, y: Int) -> ColorSample {
        let c = rgba(x: x, y: y)
        return ColorSample(
            red: c.red, green: c.green, blue: c.blue, alpha: c.alpha, colorSpace: colorSpace, spaceName: spaceName)
    }
}
