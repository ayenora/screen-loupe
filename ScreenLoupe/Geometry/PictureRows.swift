import CoreGraphics
import Foundation

/// A picture's 32-bit pixels where they may be a part of a larger buffer (`ViewerFrame.bufferRect`):
/// its rows are `bytesPerRow` apart, and only `width` pixels of each belong to it.
enum PictureRows {
    /// Copies `height` rows of `width` 4-byte pixels from `source`, `sourceRow` bytes apart, to
    /// `destination`, `destinationRow` bytes apart: only the picture's own bytes of each row.
    static func copy(
        _ source: UnsafeRawPointer, sourceRow: Int, to destination: UnsafeMutableRawPointer, destinationRow: Int,
        width: Int, height: Int
    ) {
        guard width > 0, height > 0 else { return }
        for row in 0..<height {
            memcpy(destination.advanced(by: row * destinationRow), source.advanced(by: row * sourceRow), width * 4)
        }
    }

    /// The picture's rows with nothing between them, `width * 4` bytes each: what is kept of a part
    /// of a larger buffer is just the part.
    static func packed(_ base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> Data {
        guard width > 0, height > 0 else { return Data() }
        var data = Data(count: width * 4 * height)
        data.withUnsafeMutableBytes {
            copy(
                base, sourceRow: bytesPerRow, to: $0.baseAddress!, destinationRow: width * 4, width: width,
                height: height)
        }
        return data
    }

    /// Where `part` lies in a texture of `size` pixels, in its UV: offset and size; the unit square
    /// for the whole texture.
    static func uvRect(of part: PixelRect, in size: PixelSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)
        return CGRect(
            x: CGFloat(part.x) / width, y: CGFloat(part.y) / height, width: CGFloat(part.width) / width,
            height: CGFloat(part.height) / height)
    }
}
