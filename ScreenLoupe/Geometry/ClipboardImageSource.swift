/// What of the clipboard a paste takes as its image.
enum ClipboardImageSource: Equatable, Sendable {
    /// Image files copied in Finder, taken as dropped ones.
    case files
    /// Image data of this type (a uniform type identifier).
    case data(type: String)

    /// PNG first, then TIFF: the types apps put images on the clipboard in, lossless.
    static let preferredTypes = ["public.png", "public.tiff"]

    /// Image files come first: Finder puts a copied file's icon beside its URL. Files that aren't
    /// images take nothing, not their icon. Else the image data in order of fidelity: PNG, TIFF,
    /// then the first other type in the clipboard's order that `readableTypes` holds. `nil` when
    /// nothing can be read.
    static func pick(
        types: [String], hasImageFiles: Bool, hasFiles: Bool, readableTypes: Set<String>
    ) -> ClipboardImageSource? {
        if hasImageFiles { return .files }
        if hasFiles { return nil }
        if let type = preferredTypes.first(where: types.contains) { return .data(type: type) }
        return types.first(where: readableTypes.contains).map { .data(type: $0) }
    }
}
