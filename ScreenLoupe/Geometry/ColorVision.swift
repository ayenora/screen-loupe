import CoreGraphics
import Foundation

/// A colour vision the Viewer simulates: how a person with that vision sees what it shows.
enum ColorVisionMode: String, Codable, CaseIterable, Sendable {
    case protanopia, protanomaly, deuteranopia, deuteranomaly, tritanopia, greyscale

    var title: String {
        switch self {
        case .protanopia: "Protanopia"
        case .protanomaly: "Protanomaly"
        case .deuteranopia: "Deuteranopia"
        case .deuteranomaly: "Deuteranomaly"
        case .tritanopia: "Tritanopia"
        case .greyscale: "Grayscale"
        }
    }

    /// Who sees this way: the menu item's second line.
    var detail: String {
        switch self {
        case .protanopia: "No red cones · about 1 in 100 men"
        case .protanomaly: "Weak red · about 1 in 100 men"
        case .deuteranopia: "No green cones · about 1 in 100 men"
        case .deuteranomaly: "Weak green · about 5 in 100 men, the most common"
        case .tritanopia: "No blue cones · under 1 in 10,000 people"
        case .greyscale: "Contrast without color"
        }
    }

    /// The menus' groups, a separator between two: the red-green ones, tritanopia, greyscale.
    var group: Int {
        switch self {
        case .protanopia, .protanomaly, .deuteranopia, .deuteranomaly: 0
        case .tritanopia: 1
        case .greyscale: 2
        }
    }

    /// The indicator over the Viewer: "Deuteranopia · simulated".
    var indicatorLabel: String { "\(title) · simulated" }

    /// The simulation in linear sRGB. The dichromacies and the anomalies are Machado, Oliveira and
    /// Fernandes (2009), "A Physiologically-based Model for Simulation of Color Vision Deficiency":
    /// the -opias at severity 1.0, the -omalies at 0.6, from the paper's table. Greyscale is the
    /// relative luminance, Rec. 709 (sRGB) coefficients, in every channel.
    var linearSRGBMatrix: Matrix3 {
        switch self {
        case .protanopia:
            Matrix3(
                [0.152286, 1.052583, -0.204868],
                [0.114503, 0.786281, 0.099216],
                [-0.003882, -0.048116, 1.051998])
        case .protanomaly:
            Matrix3(
                [0.385450, 0.769005, -0.154455],
                [0.100526, 0.829802, 0.069673],
                [-0.007442, -0.022190, 1.029632])
        case .deuteranopia:
            Matrix3(
                [0.367322, 0.860646, -0.227968],
                [0.280085, 0.672501, 0.047413],
                [-0.011820, 0.042940, 0.968881])
        case .deuteranomaly:
            Matrix3(
                [0.547494, 0.607765, -0.155259],
                [0.181692, 0.781742, 0.036566],
                [-0.010410, 0.027275, 0.983136])
        case .tritanopia:
            Matrix3(
                [1.255528, -0.076749, -0.178779],
                [-0.078411, 0.930809, 0.147602],
                [0.004733, 0.691367, 0.303900])
        case .greyscale:
            Matrix3(Self.luminance, Self.luminance, Self.luminance)
        }
    }

    /// Relative luminance from linear sRGB (Rec. 709).
    static let luminance: [Double] = [0.2126, 0.7152, 0.0722]
}

/// The simulation button and its ▾: which mode is chosen, and whether it is on. The chosen mode is
/// kept between launches; whether it is on isn't, so the app never starts with the colours changed.
struct ColorVisionChoice: Equatable, Sendable {
    var mode: ColorVisionMode
    var isOn: Bool

    /// The eye button: the chosen mode on or off.
    func toggled() -> ColorVisionChoice {
        ColorVisionChoice(mode: mode, isOn: !isOn)
    }

    /// A mode chosen in the ▾ or the View menu: it is chosen and on.
    func turnedOn(_ mode: ColorVisionMode) -> ColorVisionChoice {
        ColorVisionChoice(mode: mode, isOn: true)
    }

    /// The mode the Viewer simulates, or `nil` while it is off.
    var active: ColorVisionMode? { isOn ? mode : nil }
}

/// A 3×3 matrix, rows first, applied to column vectors.
struct Matrix3: Equatable, Sendable {
    var rows: [[Double]]

    init(_ first: [Double], _ second: [Double], _ third: [Double]) {
        rows = [first, second, third]
    }

    /// From its three columns.
    init(columns: [[Double]]) {
        rows = (0..<3).map { row in columns.map { $0[row] } }
    }

    static let identity = Matrix3([1, 0, 0], [0, 1, 0], [0, 0, 1])

    subscript(row: Int, column: Int) -> Double { rows[row][column] }

    static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        let rows = (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + a[r, $1] * b[$1, c] } } }
        return Matrix3(rows[0], rows[1], rows[2])
    }

    static func * (m: Matrix3, v: [Double]) -> [Double] {
        m.rows.map { row in zip(row, v).reduce(0) { $0 + $1.0 * $1.1 } }
    }

    /// `nil` when it has none.
    var inverse: Matrix3? {
        let m = rows
        let cofactors = (0..<3).map { r in
            (0..<3).map { c in
                let r1 = (r + 1) % 3
                let r2 = (r + 2) % 3
                let c1 = (c + 1) % 3
                let c2 = (c + 2) % 3
                return m[r1][c1] * m[r2][c2] - m[r1][c2] * m[r2][c1]
            }
        }
        let determinant = (0..<3).reduce(0) { $0 + m[0][$1] * cofactors[0][$1] }
        guard abs(determinant) > 1e-12 else { return nil }
        // The inverse is the transposed cofactors over the determinant.
        let rows = (0..<3).map { r in (0..<3).map { c in cofactors[c][r] / determinant } }
        return Matrix3(rows[0], rows[1], rows[2])
    }
}

/// A simulation for pixels encoded in a colour space: the values the Viewer shows are in the
/// source display's colour space (often Display P3) or an opened image's own, not sRGB, so the
/// sRGB-defined matrix can't be applied to them as they are.
///
/// Each pixel is decoded to the space's linear light through its own transfer curve (`decode`, one
/// entry per 8-bit value), taken to linear sRGB by the space's primaries (`toLinearSRGB`, white
/// kept white: relative colorimetric), simulated there, and taken back — the three matrices made
/// into one, `matrix` — then clamped to 0...1 and encoded through the curve again (`encode`). The
/// curves and the primaries are read from the colour space with ColorSync, so any matrix-based
/// profile works, not just the ones with the sRGB curve.
///
/// The Viewer's shader does this per pixel; `apply` is the same arithmetic on the CPU.
struct ColorVisionTransform: Sendable {
    /// Linear light of the space to simulated linear light of the space.
    let matrix: Matrix3
    /// An 8-bit value's linear light, per channel (red, green, blue).
    let decode: [[Float]]
    /// Linear light back to an encoded value, per channel. Entry `i` is the value of linear light
    /// `(i / (encodeCount - 1))²`: steps in the square root put more of them in the dark, where the
    /// curves are steep.
    let encode: [[Float]]

    static let encodeCount = 1024

    /// `nil` for a space that is not RGB and matrix-based.
    init?(mode: ColorVisionMode, space: CGColorSpace) {
        guard let linear = CGColorSpaceCreateLinearized(space),
            let toSRGB = Self.toLinearSRGB(space),
            let fromSRGB = toSRGB.inverse
        else { return nil }
        matrix = fromSRGB * mode.linearSRGBMatrix * toSRGB
        func table(
            _ count: Int, from source: CGColorSpace, to target: CGColorSpace, _ value: (Int) -> Double
        )
            -> [[Float]]?
        {
            var channels: [[Float]] = [[], [], []]
            for index in 0..<count {
                let v = CGFloat(value(index))
                guard let color = CGColor(colorSpace: source, components: [v, v, v, 1]),
                    let converted = color.converted(to: target, intent: .relativeColorimetric, options: nil),
                    let c = converted.components, c.count >= 3
                else { return nil }
                for channel in 0..<3 { channels[channel].append(Float(c[channel])) }
            }
            return channels
        }
        let last = Double(Self.encodeCount - 1)
        guard let decode = table(256, from: space, to: linear, { Double($0) / 255 }),
            let encode = table(Self.encodeCount, from: linear, to: space, { pow(Double($0) / last, 2) })
        else { return nil }
        self.decode = decode
        self.encode = encode
    }

    /// The space's linear light to linear sRGB: its primaries in linear sRGB, as columns. `nil`
    /// for a space that is not RGB and matrix-based.
    static func toLinearSRGB(_ space: CGColorSpace) -> Matrix3? {
        guard space.model == .rgb, let linear = CGColorSpaceCreateLinearized(space),
            let target = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        else { return nil }
        var columns: [[Double]] = []
        for primary in [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]] {
            guard let color = CGColor(colorSpace: linear, components: primary.map { CGFloat($0) } + [1]),
                let converted = color.converted(to: target, intent: .relativeColorimetric, options: nil),
                let c = converted.components, c.count >= 3
            else { return nil }
            columns.append(c.prefix(3).map { Double($0) })
        }
        return Matrix3(columns: columns)
    }

    /// One pixel of 8-bit values, simulated: what the shader returns for it, to 8 bits.
    func apply(_ pixel: [UInt8]) -> [UInt8] {
        let light = (0..<3).map { Double(decode[$0][Int(pixel[$0])]) }
        let simulated = (matrix * light).map { min(max($0, 0), 1) }
        return (0..<3).map { UInt8((min(max(encoded(simulated[$0], channel: $0), 0), 1) * 255).rounded()) }
    }

    /// The encoded value of linear light `light`, 0...1, in `channel`: between the two nearest
    /// entries of `encode`, as the shader reads it.
    func encoded(_ light: Double, channel: Int) -> Double {
        let table = encode[channel]
        let at = light.squareRoot() * Double(table.count - 1)
        let low = Int(at.rounded(.down))
        let high = min(low + 1, table.count - 1)
        let t = at - Double(low)
        return Double(table[low]) * (1 - t) + Double(table[high]) * t
    }
}
