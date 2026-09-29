import CoreGraphics

/// Where an image added to the Viewer goes.
enum ImageDestination: Equatable, Sendable {
    /// A reference layer on top (References).
    case references
    /// A Recent Captures row, shown in place of the live view (Open Image).
    case captures
}

/// Whether a dropped or pasted image goes straight to a destination or a menu asks.
enum ImagePlacement: Equatable, Sendable {
    case place(ImageDestination)
    /// A menu asks: Add as Reference, or Open for Inspection.
    case ask

    /// `chosen` is Edit › Paste as Reference or Paste for Inspection, which go where they say.
    /// Otherwise — a drop or Edit › Paste — the open panel decides: References first, then Recent
    /// Captures; with neither open, a menu asks.
    static func of(chosen: ImageDestination?, showsReferences: Bool, showsCaptures: Bool) -> ImagePlacement {
        if let chosen { return .place(chosen) }
        if showsReferences { return .place(.references) }
        if showsCaptures { return .place(.captures) }
        return .ask
    }

    /// Where the menu that asks about a pasted image comes up: at the pointer when it is over the
    /// image area, else at the area's centre. `pointer` and `imageArea` are in the same view's
    /// coordinates; `nil` when the pointer isn't known.
    static func menuPoint(pointer: CGPoint?, imageArea: CGRect) -> CGPoint {
        if let pointer, imageArea.contains(pointer) { return pointer }
        return CGPoint(x: imageArea.midX, y: imageArea.midY)
    }
}
