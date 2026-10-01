import CoreGraphics
import Foundation

/// An sRGB colour of the studio's background, each component 0...1.
struct BackgroundColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From 8-bit components.
    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// Components clamped to 0...1: a colour from the colour panel outside sRGB, or saved data.
    init(clampingRed red: Double, green: Double, blue: Double) {
        func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }
        self.init(red: clamped(red), green: clamped(green), blue: clamped(blue))
    }

    /// Components out of 0...1 are clamped, so saved data can't make a colour outside sRGB.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            clampingRed: try c.decode(Double.self, forKey: .red), green: try c.decode(Double.self, forKey: .green),
            blue: try c.decode(Double.self, forKey: .blue))
    }

    static let white = BackgroundColor(255, 255, 255)
    static let lightGray = BackgroundColor(229, 229, 234)
    static let black = BackgroundColor(0, 0, 0)
}

/// Two colours, the first at the picture's top edge and the second at its bottom edge.
struct BackgroundGradient: Codable, Hashable, Sendable {
    var top: BackgroundColor
    var bottom: BackgroundColor
}

/// An image chosen as the background, copied into the app's container.
struct BackgroundImage: Codable, Hashable, Sendable {
    /// The copy's file name in the app's container.
    var fileName: String
    /// The chosen file's name, shown in the lists.
    var name: String
}

/// What the Screenshot studio shows under the windows. Anything
/// but `screen` is shown by the backdrop over the whole display the frame is on (`StudioBackdrop`),
/// above the wallpaper and the desktop icons. One Window's picture has none: the window alone, on
/// transparency.
enum StudioBackground: Codable, Hashable, Sendable {
    /// The real desktop: no backdrop.
    case screen
    case color(BackgroundColor)
    case gradient(BackgroundGradient)
    case image(BackgroundImage)

    /// The colours offered in the lists, with their names.
    static let colors: [(name: String, color: BackgroundColor)] = [
        ("White", .white), ("Light Gray", .lightGray), ("Black", .black),
    ]

    /// Calm two-colour gradients offered in the lists, with their names.
    static let gradients: [(name: String, gradient: BackgroundGradient)] = [
        ("Mist", BackgroundGradient(top: BackgroundColor(242, 244, 248), bottom: BackgroundColor(208, 215, 228))),
        ("Dusk", BackgroundGradient(top: BackgroundColor(70, 82, 140), bottom: BackgroundColor(150, 110, 170))),
        ("Sand", BackgroundGradient(top: BackgroundColor(250, 240, 225), bottom: BackgroundColor(228, 204, 176))),
    ]

    /// A colour of the user's own: a colour background that isn't one of `colors`.
    var isCustomColor: Bool {
        guard case .color(let color) = self else { return false }
        return !Self.colors.contains { $0.color == color }
    }

    /// Where a gradient runs in a picture of `size`, in CoreGraphics coordinates (y up): from the
    /// middle of the top edge to the middle of the bottom edge.
    static func gradientLine(in size: CGSize) -> (start: CGPoint, end: CGPoint) {
        (CGPoint(x: size.width / 2, y: size.height), CGPoint(x: size.width / 2, y: 0))
    }

    /// Where an image of `imageSize` is drawn to fill a picture of `size`: scaled, keeping its
    /// proportions, until it covers the whole picture, and centred, so what sticks out is cut
    /// evenly on both sides. `.zero` for an empty image.
    static func imageRect(_ imageSize: CGSize, filling size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width,
            height: drawn.height)
    }
}

extension KeyedDecodingContainer {
    /// The saved background, or the screen when it is missing, unreadable, or an image whose file
    /// name is empty, `.`, `..` or a path: the copy lies directly in the app's folder for it.
    func studioBackground(_ key: Key) -> StudioBackground {
        let background = value(key, or: StudioBackground.screen)
        if case .image(let image) = background,
            ["", ".", ".."].contains(image.fileName) || image.fileName.contains("/")
        {
            return .screen
        }
        return background
    }
}
