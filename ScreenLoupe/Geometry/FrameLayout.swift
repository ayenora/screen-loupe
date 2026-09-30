import CoreGraphics

/// How the pixels of the picture the Viewer shows are laid out: a live frame, a frozen one or a
/// recent capture. Every tool counts pixels from the picture's top-left, so
/// they all work on each of them alike.
struct FrameLayout: Codable, Equatable, Sendable {
    /// The whole picture in pixels: the Capture Area, or the part a recent capture keeps of it.
    var size: PixelSize
    /// Top-left corner of the frame's pixels inside the picture. Non-zero only when the area
    /// straddles two displays and part of it lies on the other one, which the frame lacks.
    var imageOrigin: CGPoint
    /// The frame's pixels.
    var imageSize: PixelSize
    /// Pixels per point, for lengths in points: the capturing display's scale.
    var scale: CGFloat
}

extension FrameLayout {
    /// A whole image of `image` pixels, one pixel per point.
    init(image: PixelSize) {
        self.init(size: image, imageOrigin: .zero, imageSize: image, scale: 1)
    }

    /// Where the frame goes in an image of the whole picture, in that image's pixels with
    /// CoreGraphics' bottom-left origin (Copy Source).
    var imageRectInAreaImage: CGRect {
        CGRect(
            x: imageOrigin.x, y: CGFloat(size.height) - imageOrigin.y - CGFloat(imageSize.height),
            width: CGFloat(imageSize.width), height: CGFloat(imageSize.height))
    }

    /// The picture cut to `rect`, whole pixels from its top-left: the picture becomes `rect` and the
    /// frame the part of it inside `rect`. `offset` is where that part starts in the frame, to copy
    /// from. `nil` when none of the frame is inside. For a snapshot of the part the Viewer shows or
    /// of a selection.
    func cropped(toArea rect: CGRect) -> (layout: FrameLayout, offset: PixelSize)? {
        let image = CGRect(
            x: imageOrigin.x, y: imageOrigin.y, width: CGFloat(imageSize.width), height: CGFloat(imageSize.height))
        let inside = image.intersection(rect.integral)
        guard !inside.isNull, inside.width >= 1, inside.height >= 1 else { return nil }
        var next = self
        next.size = PixelSize(width: Int(rect.integral.width), height: Int(rect.integral.height))
        next.imageOrigin = CGPoint(x: inside.minX - rect.integral.minX, y: inside.minY - rect.integral.minY)
        next.imageSize = PixelSize(width: Int(inside.width), height: Int(inside.height))
        let offset = PixelSize(width: Int(inside.minX - imageOrigin.x), height: Int(inside.minY - imageOrigin.y))
        return (next, offset)
    }

    /// The picture kept as a recent capture: cut to `ImageBudget` from its top-left, and the frame
    /// cut to the part inside it, which stays at the same place. The frame's top-left part of
    /// `imageSize` is what to copy. `nil` when none of the frame is left (an area straddling two
    /// displays, cut before it reaches that part).
    func fittedToImageBudget() -> FrameLayout? {
        let kept = ImageBudget.fitted(width: size.width, height: size.height)
        let width = min(imageSize.width, kept.width - Int(imageOrigin.x))
        let height = min(imageSize.height, kept.height - Int(imageOrigin.y))
        guard width > 0, height > 0 else { return nil }
        var next = self
        next.size = PixelSize(width: kept.width, height: kept.height)
        next.imageSize = PixelSize(width: width, height: height)
        return next
    }
}

extension CaptureGeometry {
    /// How a frame captured with this geometry is laid out: the whole area, the captured part of it,
    /// and the capturing display's scale.
    var layout: FrameLayout {
        FrameLayout(size: areaSize, imageOrigin: imageOrigin, imageSize: outputSize, scale: display.scale)
    }
}
