import Foundation

/// How saved screenshots are named.
enum FileNameStyle: String, Codable, CaseIterable, Sendable {
    /// `Screen Loupe View 2026-09-24 at 14.20.05`, like macOS screenshots.
    case macOS
    /// `ScreenLoupe-View-20260924-142005`.
    case compact
}

/// The name the save panel suggests (Settings › Screenshots): `Screen Loupe View 2026-09-24 at
/// 14.20.05.png`, in the style of macOS screenshots, or `ScreenLoupe-View-20260924-142005.png`.
/// With a `size`, the picture's pixels follow the time: `… at 14.20.05 2880×1800.png`, or
/// `…-142005-2880x1800.png`.
enum ScreenshotName {
    static func fileName(
        kind: String, style: FileNameStyle, size: PixelSize? = nil, fileExtension: String = "png",
        date: Date = Date(), timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        switch style {
        case .macOS:
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let pixels = size.map { " \($0.width)×\($0.height)" } ?? ""
            return "Screen Loupe \(kind) \(formatter.string(from: date))\(pixels).\(fileExtension)"
        case .compact:
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let pixels = size.map { "-\($0.width)x\($0.height)" } ?? ""
            return "ScreenLoupe-\(kind)-\(formatter.string(from: date))\(pixels).\(fileExtension)"
        }
    }
}
