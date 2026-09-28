import Testing

struct ClipboardImageSourceTests {
    private let readable: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "public.heic", "com.apple.icns", "org.webmproject.webp",
    ]

    private func pick(_ types: [String], imageFiles: Bool = false, files: Bool = false) -> ClipboardImageSource? {
        ClipboardImageSource.pick(types: types, hasImageFiles: imageFiles, hasFiles: files, readableTypes: readable)
    }

    @Test func pngComesFirst() {
        #expect(pick(["public.tiff", "public.jpeg", "public.png"]) == .data(type: "public.png"))
    }

    @Test func tiffComesBeforeOtherTypes() {
        #expect(pick(["public.jpeg", "public.heic", "public.tiff"]) == .data(type: "public.tiff"))
    }

    @Test func otherTypesGoInTheClipboardsOrder() {
        #expect(pick(["public.heic", "public.jpeg"]) == .data(type: "public.heic"))
        #expect(pick(["public.jpeg", "public.heic"]) == .data(type: "public.jpeg"))
    }

    @Test func typesItCantReadAreSkipped() {
        #expect(pick(["public.utf8-plain-text", "com.adobe.pdf", "public.jpeg"]) == .data(type: "public.jpeg"))
    }

    @Test func textAloneGivesNothing() {
        #expect(pick(["public.utf8-plain-text", "public.html", "public.url"]) == nil)
        #expect(pick([]) == nil)
    }

    /// PDF isn't taken (Open Image), so it isn't in the readable types.
    @Test func pdfAloneGivesNothing() {
        #expect(pick(["com.adobe.pdf"]) == nil)
    }

    /// Finder's Copy puts the file's URL and its icon.
    @Test func imageFilesComeBeforeTheirIcon() {
        #expect(pick(["public.file-url", "com.apple.icns", "public.tiff"], imageFiles: true, files: true) == .files)
    }

    @Test func otherFilesTakeNothingNotTheirIcon() {
        #expect(pick(["public.file-url", "com.apple.icns", "public.tiff"], files: true) == nil)
    }

    @Test func imageFilesAloneAreTaken() {
        #expect(pick(["public.file-url"], imageFiles: true, files: true) == .files)
    }

    @Test func preferredTypesAreTakenEvenIfNotListedAsReadable() {
        let source = ClipboardImageSource.pick(
            types: ["public.png"], hasImageFiles: false, hasFiles: false, readableTypes: [])
        #expect(source == .data(type: "public.png"))
    }
}
