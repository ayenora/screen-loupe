import CoreGraphics
import Foundation
import Testing

struct PictureRowsTests {
    /// A 6 × 4 buffer whose rows are padded to 32 bytes, every byte its own index.
    private let buffer: [UInt8] = (0..<32 * 4).map { UInt8($0) }
    private let bytesPerRow = 32

    /// The bytes of `width` × `height` pixels at `x`, `y` of `buffer`, row after row.
    private func expected(x: Int, y: Int, width: Int, height: Int) -> [UInt8] {
        (y..<y + height).flatMap { row in Array(buffer[row * bytesPerRow + x * 4..<row * bytesPerRow + (x + width) * 4])
        }
    }

    @Test func packedRowsHoldJustThePicturesBytes() {
        let data = buffer.withUnsafeBytes {
            PictureRows.packed($0.baseAddress!, width: 6, height: 4, bytesPerRow: bytesPerRow)
        }
        #expect(data.count == 6 * 4 * 4)
        #expect([UInt8](data) == expected(x: 0, y: 0, width: 6, height: 4))
    }

    /// A part at the buffer's bottom-right corner: only its rows and columns, nothing past its last.
    @Test func aPartIsPackedAloneUpToTheBuffersEnd() {
        let (x, y, width, height) = (4, 2, 2, 2)
        let data = buffer.withUnsafeBytes {
            PictureRows.packed(
                $0.baseAddress!.advanced(by: y * bytesPerRow + x * 4), width: width, height: height,
                bytesPerRow: bytesPerRow)
        }
        #expect(data.count == width * 4 * height)
        #expect([UInt8](data) == expected(x: x, y: y, width: width, height: height))
    }

    @Test func nothingIsPackedOfAnEmptyPicture() {
        let empty = buffer.withUnsafeBytes { PictureRows.packed($0.baseAddress!, width: 0, height: 4, bytesPerRow: 32) }
        #expect(empty.isEmpty)
        let flat = buffer.withUnsafeBytes { PictureRows.packed($0.baseAddress!, width: 4, height: 0, bytesPerRow: 32) }
        #expect(flat.isEmpty)
    }

    @Test func rowsAreCopiedToRowsOfAnotherLength() {
        var out = [UInt8](repeating: 0xFF, count: 12 * 2)
        out.withUnsafeMutableBytes { destination in
            buffer.withUnsafeBytes {
                PictureRows.copy(
                    $0.baseAddress!.advanced(by: 1 * bytesPerRow + 2 * 4), sourceRow: bytesPerRow,
                    to: destination.baseAddress!, destinationRow: 12, width: 2, height: 2)
            }
        }
        // 8 bytes of each 12-byte row are the part's; the rest is left as it was.
        #expect(Array(out[0..<8]) == Array(buffer[40..<48]))
        #expect(Array(out[8..<12]) == [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(Array(out[12..<20]) == Array(buffer[72..<80]))
        #expect(Array(out[20..<24]) == [0xFF, 0xFF, 0xFF, 0xFF])
    }

    @Test func theWholeTextureIsTheUnitSquare() {
        #expect(
            PictureRows.uvRect(
                of: PixelRect(x: 0, y: 0, width: 2880, height: 1800), in: PixelSize(width: 2880, height: 1800))
                == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func aPartIsItsShareOfTheTexture() {
        let rect = PictureRows.uvRect(
            of: PixelRect(x: 720, y: 450, width: 1440, height: 900), in: PixelSize(width: 2880, height: 1800))
        #expect(rect == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test func anEmptyTextureIsTheUnitSquare() {
        #expect(
            PictureRows.uvRect(of: PixelRect(x: 1, y: 1, width: 1, height: 1), in: PixelSize(width: 0, height: 10))
                == CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
