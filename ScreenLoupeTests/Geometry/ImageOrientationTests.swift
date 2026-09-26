import Testing

struct ImageOrientationTests {
    /// Where stored pixel (x, y) of a `width` × `height` image lands once `orientation` is applied:
    /// mirrored left to right, then turned clockwise.
    private func upright(_ x: Int, _ y: Int, width: Int, height: Int, _ orientation: ImageOrientation) -> [Int] {
        var (x, y, width, height) = (x, y, width, height)
        if orientation.mirrored { x = width - 1 - x }
        for _ in 0..<orientation.quarterTurns {
            (x, y, width, height) = (height - 1 - y, x, height, width)
        }
        return [x, y]
    }

    /// EXIF's own definition: where the stored first row's first and last pixels end up in the
    /// upright image, 3 × 2 stored. Two corners fix the whole transform.
    static let exifCases: [(Int, [Int], [Int])] = [
        (1, [0, 0], [2, 0]),
        (2, [2, 0], [0, 0]),
        (3, [2, 1], [0, 1]),
        (4, [0, 1], [2, 1]),
        (5, [0, 0], [0, 2]),
        (6, [1, 0], [1, 2]),
        (7, [1, 2], [1, 0]),
        (8, [0, 2], [0, 0]),
    ]

    @Test(arguments: exifCases)
    func everyOrientationMatchesExif(exif: Int, firstPixel: [Int], lastPixelOfFirstRow: [Int]) {
        let orientation = ImageOrientation(exif: exif)
        #expect(upright(0, 0, width: 3, height: 2, orientation) == firstPixel)
        #expect(upright(2, 0, width: 3, height: 2, orientation) == lastPixelOfFirstRow)
        #expect(orientation.swapsSides == (exif >= 5))
        #expect(orientation.isUpright == (exif == 1))
    }

    @Test func anUnknownOrientationIsUpright() {
        #expect(ImageOrientation(exif: 0).isUpright)
        #expect(ImageOrientation(exif: 9).isUpright)
    }
}
