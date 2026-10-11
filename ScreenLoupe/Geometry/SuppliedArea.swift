/// What follows the picture the Viewer shows while an area may be supplied in place of the Capture
/// Area (`WindowManager.suppliedArea`): the frame shown decides, not the area supplied now.
enum SuppliedArea {
    /// Where the real pointer is placed in the picture.
    enum PointerPlace: Equatable, Sendable {
        /// In the shown frame's geometry: a frozen frame, or the supplied area.
        case geometry(CaptureGeometry)
        /// In the Capture Area as it is now.
        case captureArea
        /// Nowhere.
        case none
    }

    /// While an area is supplied, or the Capture Area's frame shows: in a frozen frame's own
    /// geometry while one shows — the picture is where the area was when it froze, wherever it is
    /// now — else in the supplied area, else in the Capture Area. A recent capture or an opened image
    /// has no place in it (`frozen` is `nil` then, and the caller doesn't ask).
    static func pointerPlace(frozen: CaptureGeometry?, supplied: CaptureGeometry?, areaShown: Bool) -> PointerPlace {
        guard supplied != nil || areaShown else { return .none }
        if let frozen { return .geometry(frozen) }
        if let supplied { return .geometry(supplied) }
        return .captureArea
    }

    /// Whether the Viewer keeps the picture centred (`ZoomPanController.keepsContentCentered`): only
    /// the live view of an area that asks for it; a still picture — frozen, a recent capture, an
    /// opened image — pans as always.
    static func keepsCentered(centersLiveView: Bool, showsStill: Bool) -> Bool {
        centersLiveView && !showsStill
    }
}
