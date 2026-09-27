import CoreGraphics

/// Where a studio palette button takes the mouse (docs/design.md, The palette): only where it shows,
/// inside its group's rounded outline. Its square corners outside that outline are the window's
/// background, so a mouse-down there drags the palette.
enum PaletteHitShape {
    /// Whether `point` is inside `rect` with corners rounded by `radius`, clamped to half the
    /// shorter side (a capsule at most), as `NSBezierPath(roundedRect:xRadius:yRadius:)` draws it.
    /// The edges and the arcs themselves count as inside.
    static func contains(_ point: CGPoint, roundedRect rect: CGRect, radius: CGFloat) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        guard point.x >= rect.minX, point.x <= rect.maxX, point.y >= rect.minY, point.y <= rect.maxY else {
            return false
        }
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        // The nearest corner's arc centre; outside the corner squares the straight edges hold.
        let cx = min(max(point.x, rect.minX + r), rect.maxX - r)
        let cy = min(max(point.y, rect.minY + r), rect.maxY - r)
        let dx = point.x - cx
        let dy = point.y - cy
        return dx * dx + dy * dy <= r * r
    }

    /// Whether a button with `buttonFrame` in its group's coordinates takes the mouse at `point`,
    /// in the same coordinates: inside the button and inside the group's rounded outline, `group`
    /// with `radius`. The button's frame is half-open, as `NSView` hit-testing takes it, so where
    /// two buttons touch only one takes the point.
    static func buttonTakes(_ point: CGPoint, buttonFrame: CGRect, group: CGRect, radius: CGFloat) -> Bool {
        buttonFrame.contains(point) && contains(point, roundedRect: group, radius: radius)
    }
}
