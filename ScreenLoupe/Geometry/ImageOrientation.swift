/// How to turn an image stored with an EXIF orientation upright (docs/design.md §2): mirrored left
/// to right first, then turned clockwise by quarter turns. For an opened image and reference layers.
struct ImageOrientation: Equatable, Sendable {
    var mirrored: Bool
    /// Clockwise quarter turns, 0...3.
    var quarterTurns: Int

    /// EXIF orientation 1...8; anything else is upright.
    init(exif: Int) {
        switch exif {
        case 2: (mirrored, quarterTurns) = (true, 0)
        case 3: (mirrored, quarterTurns) = (false, 2)
        case 4: (mirrored, quarterTurns) = (true, 2)
        case 5: (mirrored, quarterTurns) = (true, 3)
        case 6: (mirrored, quarterTurns) = (false, 1)
        case 7: (mirrored, quarterTurns) = (true, 1)
        case 8: (mirrored, quarterTurns) = (false, 3)
        default: (mirrored, quarterTurns) = (false, 0)
        }
    }

    var isUpright: Bool { !mirrored && quarterTurns == 0 }

    /// Whether the upright image's width is the stored height (orientations 5–8).
    var swapsSides: Bool { quarterTurns % 2 == 1 }
}
