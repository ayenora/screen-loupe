import AppKit

/// Images coming into the Viewer from outside (docs/product.md, Dropping and pasting images): image
/// files dropped or copied in Finder, or image data on the clipboard.
enum ImageInput {
    case files([URL])
    case data(Data, type: String)

    /// The name a pasted image's row and layer take: it has no file.
    static let pastedName = "Pasted image"

    /// The image files on `pasteboard`, of the types Open Image and Add… take; the rest are ignored.
    static func imageFileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: imageFileOptions) as? [URL] ?? []
    }

    private static var imageFileOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ImageFileLoader.openableTypes.map(\.identifier),
        ]
    }

    /// What of `pasteboard` a paste would take (`ClipboardImageSource`), from its types alone: cheap
    /// enough for validating a menu item.
    private static func source(on pasteboard: NSPasteboard) -> ClipboardImageSource? {
        let urls = [NSURL.self]
        return ClipboardImageSource.pick(
            types: pasteboard.types?.map(\.rawValue) ?? [],
            hasImageFiles: pasteboard.canReadObject(forClasses: urls, options: imageFileOptions),
            hasFiles: pasteboard.canReadObject(forClasses: urls, options: [.urlReadingFileURLsOnly: true]),
            readableTypes: Set(ImageFileLoader.openableTypes.map(\.identifier)))
    }

    /// Whether the clipboard holds an image a paste can take.
    static var isOnClipboard: Bool { source(on: .general) != nil }

    /// The image on the clipboard, or `nil` when it holds none that can be read.
    static func fromClipboard() -> ImageInput? {
        let pasteboard = NSPasteboard.general
        switch source(on: pasteboard) {
        case .files?:
            let urls = imageFileURLs(on: pasteboard)
            return urls.isEmpty ? nil : .files(urls)
        case .data(let type)?:
            return pasteboard.data(forType: NSPasteboard.PasteboardType(type)).map { .data($0, type: type) }
        case nil:
            return nil
        }
    }
}
