import AppKit
import CoreVideo

/// A colour the user pinned by clicking in the Viewer.
struct PinnedColor: Codable, Equatable {
    var hex: String
    var nativeValues: String
    var nativeSpaceName: String
    /// Where it was picked, in Capture Area pixels.
    var x: Int
    var y: Int

    var sample: ColorSample { ColorSample(srgbHex: hex) }
}

/// The pixel being inspected and the pinned colours (docs/product.md, Color Meter).
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

    static let maxPins = 8

    private(set) var probe: Probe?
    private(set) var pins: [PinnedColor]
    var onChange: (() -> Void)?

    private let frameStore: FrameStore
    private let settings: SettingsStore
    private var viewerPixel: (x: Int, y: Int)?
    private var areaPixel: (x: Int, y: Int)?

    init(frameStore: FrameStore, settings: SettingsStore) {
        self.frameStore = frameStore
        self.settings = settings
        // An older version kept more; the newest stay.
        pins = Array(settings.settings.pinnedColors.prefix(Self.maxPins))
    }

    // MARK: Pointing

    func setViewerPixel(_ pixel: (x: Int, y: Int)?) {
        viewerPixel = pixel
        update()
    }

    func setAreaPixel(_ pixel: (x: Int, y: Int)?) {
        areaPixel = pixel
        update()
    }

    /// A new frame: the colour under a pointer that didn't move may still have changed.
    func frameArrived() {
        guard probe != nil else { return }
        update()
    }

    private func update() {
        let next: Probe?
        if let pixel = viewerPixel {
            next = Probe(source: .viewer, x: pixel.x, y: pixel.y, sample: sample(atAreaPixel: pixel))
        } else if let pixel = areaPixel {
            next = Probe(source: .captureArea, x: pixel.x, y: pixel.y, sample: sample(atAreaPixel: pixel))
        } else {
            next = nil
        }
        guard next != probe else { return }
        probe = next
        onChange?()
    }

    /// The colour of a Capture Area pixel in the latest frame.
    private func sample(atAreaPixel pixel: (x: Int, y: Int)) -> ColorSample? {
        guard let frame = frameStore.latestFrame else { return nil }
        let x = pixel.x - Int(frame.geometry.imageOrigin.x)
        let y = pixel.y - Int(frame.geometry.imageOrigin.y)
        let size = frame.pixelSize
        guard x >= 0, y >= 0, x < size.width, y < size.height else { return nil }

        let buffer = frame.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytes = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        // 32BGRA.
        let displayID = frame.geometry.display.id
        return ColorSample(
            red: bytes[2], green: bytes[1], blue: bytes[0],
            colorSpace: NSScreen.colorSpace(forDisplay: displayID),
            spaceName: NSScreen.screen(forDisplay: displayID)?.colorSpace?.localizedName)
    }

    // MARK: Pins

    /// Pins the inspected colour; returns it, or `nil` when there is nothing to pin.
    @discardableResult
    func pinProbe() -> PinnedColor? {
        guard let probe, let sample = probe.sample else { return nil }
        let pin = PinnedColor(
            hex: sample.hex, nativeValues: sample.nativeValues, nativeSpaceName: sample.nativeSpaceName,
            x: probe.x, y: probe.y)
        pins.insert(pin, at: 0)
        if pins.count > Self.maxPins { pins.removeLast(pins.count - Self.maxPins) }
        pinsChanged()
        return pin
    }

    func removePin(at index: Int) {
        guard pins.indices.contains(index) else { return }
        pins.remove(at: index)
        pinsChanged()
    }

    func clearPins() {
        pins.removeAll()
        pinsChanged()
    }

    private func pinsChanged() {
        settings.update { $0.pinnedColors = pins }
        onChange?()
    }
}
