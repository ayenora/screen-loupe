import CoreGraphics
import Testing

struct PixelGridTests {
    @Test func linesAreTheFirstDrawablePixelOfEverySourcePixel() {
        let lines = (0..<12).filter { PixelGrid.isLine($0, start: 0, zoom: 4) }
        #expect(lines == [0, 4, 8])
    }

    @Test func linesFollowTheImageOrigin() {
        let lines = (0..<12).filter { PixelGrid.isLine($0, start: -3, zoom: 4) }
        #expect(lines == [1, 5, 9])
    }

    @Test func drawsOnlyLinesInsideTheImage() {
        // A 6 × 1 viewport, mid-grey, with a 1 × 1 source pixel at zoom 4 placed from column 1.
        let width = 6
        var bytes = [UInt8](repeating: 128, count: width * 4)
        bytes.withUnsafeMutableBufferPointer {
            PixelGrid.draw(
                into: $0.baseAddress!, width: width, height: 1, bytesPerRow: width * 4,
                imageRect: CGRect(x: 1, y: 0, width: 4, height: 1), zoom: 4, lines: .dark)
        }
        let reds = stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
        // Row 0 is the image's top edge: every image pixel in it is a line; outside stays.
        #expect(reds == [128, 100, 100, 100, 100, 128])
    }

    @Test func autoLinesContrastWithThePixel() {
        #expect(gridded([255, 255, 255, 255], lines: .auto)[0] == 199)
        #expect(gridded([0, 0, 0, 255], lines: .auto)[0] == 56)
        #expect(gridded([0, 0, 0, 255], lines: .dark)[0] == 0)
    }

    /// One pixel that lies on a line.
    private func gridded(_ pixel: [UInt8], lines: GridLines) -> [UInt8] {
        var bytes = pixel
        bytes.withUnsafeMutableBufferPointer {
            PixelGrid.draw(
                into: $0.baseAddress!, width: 1, height: 1, bytesPerRow: 4,
                imageRect: CGRect(x: 0, y: 0, width: 8, height: 8), zoom: 8, lines: lines)
        }
        return bytes
    }
}
