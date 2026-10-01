import CoreGraphics

// Each coordinate system has its own type so the compiler refuses to mix them.

/// AppKit global coordinates: points, origin at the bottom-left of the primary display, y up.
/// Secondary displays can have negative coordinates.
struct GlobalRect: Equatable, Sendable {
    var rect: CGRect
}

/// Quartz global coordinates: points, origin at the top-left of the primary display, y down.
/// `SCDisplay.frame` and `CGDisplayBounds` use this system.
struct QuartzRect: Equatable, Sendable {
    var rect: CGRect
}

/// Points relative to the top-left corner of one display, y down.
/// This is what `SCStreamConfiguration.sourceRect` expects.
struct DisplayLocalRect: Equatable, Sendable {
    var displayID: CGDirectDisplayID
    var rect: CGRect
}

/// Whole pixels of an image, origin at its top-left corner, y down.
struct PixelSize: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
}

/// A rect of whole pixels in an image, origin at its top-left corner, y down.
struct PixelRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var size: PixelSize { PixelSize(width: width, height: height) }
}

/// A display as the geometry layer sees it.
struct DisplayInfo: Equatable, Sendable {
    var id: CGDirectDisplayID
    /// Frame in AppKit global coordinates. Display frames are whole points.
    var globalFrame: CGRect
    /// Backing scale factor: pixels per point.
    var scale: CGFloat
}
