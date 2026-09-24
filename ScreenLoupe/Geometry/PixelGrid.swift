import CoreGraphics

/// The pixel grid's line colour (Settings › Viewer). Auto draws dark lines over light pixels and
/// light lines over dark ones.
enum GridLines: String, Codable, CaseIterable, Sendable {
    case auto, dark, light
}

/// The pixel grid drawn into an exported Capture View exactly as the Viewer's shader draws it
/// (`ViewerShaders`): the first drawable pixel of every source pixel, on its left and top edge, is
/// the line, blended over the pixel.
enum PixelGrid {
    /// How strongly a line covers the pixel under it. The shader takes this and `lumaWeights` from here.
    static let opacity = 0.22
    /// Auto lines turn dark where the pixel's luma, weighted like this, is above 0.5.
    static let lumaWeights = (red: 0.2126, green: 0.7152, blue: 0.0722)

    private static func isLight(red: Double, green: Double, blue: Double) -> Bool {
        lumaWeights.red * red + lumaWeights.green * green + lumaWeights.blue * blue > 0.5
    }

    /// Whether viewport pixel `index` (a column or a row) lies on a line, for an image placed from
    /// `start` at `zoom` drawable pixels per source pixel. Measured at the pixel's centre.
    static func isLine(_ index: Int, start: CGFloat, zoom: CGFloat) -> Bool {
        let into = (CGFloat(index) + 0.5 - start) / zoom
        return (into - into.rounded(.down)) * zoom < 1
    }

    /// Blends the grid into opaque 8-bit RGBA pixels, rows top to bottom, over `imageRect` (viewport
    /// pixels, y down) only.
    static func draw(
        into bytes: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, imageRect: CGRect,
        zoom: CGFloat, lines: GridLines
    ) {
        let columns = max(0, Int(imageRect.minX.rounded()))..<min(width, Int(imageRect.maxX.rounded()))
        let rows = max(0, Int(imageRect.minY.rounded()))..<min(height, Int(imageRect.maxY.rounded()))
        guard !columns.isEmpty, !rows.isEmpty else { return }
        let lineColumns = columns.map { isLine($0, start: imageRect.minX, zoom: zoom) }
        for row in rows {
            let rowIsLine = isLine(row, start: imageRect.minY, zoom: zoom)
            let rowStart = bytes + row * bytesPerRow
            for (offset, column) in columns.enumerated() where rowIsLine || lineColumns[offset] {
                blend(rowStart + column * 4, lines: lines)
            }
        }
    }

    private static func blend(_ pixel: UnsafeMutablePointer<UInt8>, lines: GridLines) {
        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        let line: Double
        switch lines {
        case .auto: line = isLight(red: red, green: green, blue: blue) ? 0 : 1
        case .dark: line = 0
        case .light: line = 1
        }
        for (index, value) in [red, green, blue].enumerated() {
            pixel[index] = UInt8(((value + (line - value) * opacity) * 255).rounded())
        }
    }
}
