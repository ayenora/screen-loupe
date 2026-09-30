import CoreGraphics
import Foundation
import Testing

struct ColorVisionTests {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    private static let adobeRGB = CGColorSpace(name: CGColorSpace.adobeRGB1998)!
    private static let spaces = [sRGB, displayP3, adobeRGB]

    /// The sRGB curve, as IEC 61966-2-1 gives it.
    private static func srgbDecode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func srgbEncode(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    private static func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }

    private func transform(_ mode: ColorVisionMode, _ space: CGColorSpace) throws -> ColorVisionTransform {
        try #require(ColorVisionTransform(mode: mode, space: space))
    }

    private func expectClose(_ a: Matrix3, _ b: Matrix3, within tolerance: Double) {
        for r in 0..<3 {
            for c in 0..<3 {
                #expect(abs(a[r, c] - b[r, c]) < tolerance, "[\(r), \(c)]: \(a[r, c]) vs \(b[r, c])")
            }
        }
    }

    private func expectWithinOne(_ a: [UInt8], _ b: [UInt8]) {
        #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 1 }, "\(a) vs \(b)")
    }

    // MARK: The matrices

    @Test func theMatricesAreMachadoOliveiraAndFernandes() {
        // Spot checks against the paper's table: the dichromacies at severity 1.0, the anomalies at 0.6.
        #expect(ColorVisionMode.protanopia.linearSRGBMatrix.rows[0] == [0.152286, 1.052583, -0.204868])
        #expect(ColorVisionMode.deuteranopia.linearSRGBMatrix.rows[1] == [0.280085, 0.672501, 0.047413])
        #expect(ColorVisionMode.tritanopia.linearSRGBMatrix.rows[2] == [0.004733, 0.691367, 0.303900])
        #expect(ColorVisionMode.protanomaly.linearSRGBMatrix.rows[0] == [0.385450, 0.769005, -0.154455])
        #expect(ColorVisionMode.deuteranomaly.linearSRGBMatrix.rows[0] == [0.547494, 0.607765, -0.155259])
    }

    @Test func everyRowSumsToOneSoGreysStayGrey() {
        for mode in ColorVisionMode.allCases {
            for row in mode.linearSRGBMatrix.rows {
                #expect(abs(row.reduce(0, +) - 1) < 2e-6, "\(mode)")
            }
        }
    }

    @Test func greyscaleIsTheRec709LuminanceInEveryChannel() {
        let rows = ColorVisionMode.greyscale.linearSRGBMatrix.rows
        #expect(rows.allSatisfy { $0 == [0.2126, 0.7152, 0.0722] })
    }

    // MARK: Matrix3

    @Test func theInverseUndoesTheMatrix() throws {
        for mode in ColorVisionMode.allCases where mode != .greyscale {
            let m = mode.linearSRGBMatrix
            expectClose(try #require(m.inverse) * m, .identity, within: 1e-9)
        }
    }

    @Test func aSingularMatrixHasNoInverse() {
        #expect(ColorVisionMode.greyscale.linearSRGBMatrix.inverse == nil)
    }

    @Test func columnsBuildTheTransposedRows() {
        let m = Matrix3(columns: [[1, 2, 3], [4, 5, 6], [7, 8, 9]])
        #expect(m.rows == [[1, 4, 7], [2, 5, 8], [3, 6, 9]])
        #expect(m * [1, 0, 0] == [1, 2, 3])
    }

    // MARK: Colour spaces

    @Test func sRGBNeedsNoConversion() throws {
        expectClose(try #require(ColorVisionTransform.toLinearSRGB(Self.sRGB)), .identity, within: 1e-4)
    }

    @Test func displayP3PrimariesInLinearSRGB() throws {
        let expected = Matrix3(
            [1.2249, -0.2247, 0], [-0.0420, 1.0419, 0], [-0.0197, -0.0786, 1.0979])
        expectClose(try #require(ColorVisionTransform.toLinearSRGB(Self.displayP3)), expected, within: 1e-3)
    }

    @Test func adobeRGBPrimariesInLinearSRGB() throws {
        let expected = Matrix3([1.3982, -0.3982, 0], [0, 1, 0], [0, -0.0429, 1.0429])
        expectClose(try #require(ColorVisionTransform.toLinearSRGB(Self.adobeRGB)), expected, within: 1e-3)
    }

    @Test func aSpaceThatIsNotRGBHasNoSimulation() {
        let grey = CGColorSpace(name: CGColorSpace.linearGray)!
        #expect(ColorVisionTransform.toLinearSRGB(grey) == nil)
        #expect(ColorVisionTransform(mode: .deuteranopia, space: grey) == nil)
    }

    @Test func inSRGBTheMatrixIsThePublishedOne() throws {
        for mode in ColorVisionMode.allCases {
            expectClose(try transform(mode, Self.sRGB).matrix, mode.linearSRGBMatrix, within: 1e-4)
        }
    }

    // MARK: Curves

    @Test func theSRGBCurveIsDecodedAsPublished() throws {
        let decode = try transform(.deuteranopia, Self.sRGB).decode
        for code in 0...255 {
            let expected = Self.srgbDecode(Double(code) / 255)
            for channel in 0..<3 {
                #expect(abs(Double(decode[channel][code]) - expected) < 1e-4, "\(code)")
            }
        }
    }

    @Test func everyValueComesBackThroughTheCurves() throws {
        // Without a simulation, decoding and encoding again changes nothing.
        for space in Self.spaces {
            let transform = try transform(.protanopia, space)
            for code in 0...255 {
                for channel in 0..<3 {
                    let light = Double(transform.decode[channel][code])
                    #expect(Self.byte(transform.encoded(light, channel: channel)) == UInt8(code), "\(code)")
                }
            }
        }
    }

    // MARK: Pixels

    @Test func whiteStaysWhiteAndBlackStaysBlack() throws {
        for space in Self.spaces {
            for mode in ColorVisionMode.allCases {
                let transform = try transform(mode, space)
                #expect(transform.apply([255, 255, 255]) == [255, 255, 255], "\(mode)")
                #expect(transform.apply([0, 0, 0]) == [0, 0, 0], "\(mode)")
            }
        }
    }

    @Test func everyGreyStaysTheSameGrey() throws {
        for space in Self.spaces {
            for mode in ColorVisionMode.allCases {
                let transform = try transform(mode, space)
                for code in stride(from: 0, through: 255, by: 5) {
                    let v = UInt8(code)
                    expectWithinOne(transform.apply([v, v, v]), [v, v, v])
                }
            }
        }
    }

    @Test func greyscaleOfPureSRGBColoursIsTheirLuminance() throws {
        let transform = try transform(.greyscale, Self.sRGB)
        for (pixel, luminance) in [([255, 0, 0], 0.2126), ([0, 255, 0], 0.7152), ([0, 0, 255], 0.0722)] {
            let grey = Self.byte(Self.srgbEncode(luminance))
            #expect(transform.apply(pixel.map(UInt8.init)) == [grey, grey, grey])
        }
    }

    @Test func greyscaleOfPureDisplayP3ColoursIsTheirLuminance() throws {
        // Display P3's primaries' relative luminance (its Y row, D65); P3 uses the sRGB curve.
        let transform = try transform(.greyscale, Self.displayP3)
        for (pixel, luminance) in [([255, 0, 0], 0.2290), ([0, 255, 0], 0.6917), ([0, 0, 255], 0.0793)] {
            let grey = Self.byte(Self.srgbEncode(luminance))
            expectWithinOne(transform.apply(pixel.map(UInt8.init)), [grey, grey, grey])
        }
    }

    @Test func deuteranopiaOfSRGBRedFollowsThePublishedMatrix() throws {
        // Linear red (1, 0, 0) becomes the matrix's first column, the negative blue clamped to 0.
        let expected = [0.367322, 0.280085, 0].map { Self.byte(Self.srgbEncode($0)) }
        #expect(try transform(.deuteranopia, Self.sRGB).apply([255, 0, 0]) == expected)
    }

    @Test func aDisplayP3PixelIsSimulatedInLinearSRGB() throws {
        // Independently: the P3 pixel converted to extended sRGB by ColorSync (it is outside sRGB),
        // simulated with the published matrix on the sRGB curve (mirrored below 0, as extended sRGB
        // is), converted back, and clipped to 0...1 as the shader clips.
        let pixel: [UInt8] = [204, 77, 26]
        let extended = CGColorSpace(name: CGColorSpace.extendedSRGB)!
        let extendedP3 = CGColorSpace(name: CGColorSpace.extendedDisplayP3)!
        let p3 = CGColor(colorSpace: Self.displayP3, components: pixel.map { CGFloat($0) / 255 } + [1])!
        let srgb = try #require(p3.converted(to: extended, intent: .relativeColorimetric, options: nil)?.components)
        for mode in ColorVisionMode.allCases {
            let light = srgb.prefix(3).map { v in (v < 0 ? -1 : 1) * Self.srgbDecode(abs(Double(v))) }
            let simulated = (mode.linearSRGBMatrix * light).map { l in (l < 0 ? -1 : 1) * Self.srgbEncode(abs(l)) }
            let back = CGColor(colorSpace: extended, components: simulated.map { CGFloat($0) } + [1])!
            let components = try #require(
                back.converted(to: extendedP3, intent: .relativeColorimetric, options: nil)?.components)
            let expected = components.prefix(3).map { Self.byte(Double($0)) }
            expectWithinOne(try transform(mode, Self.displayP3).apply(pixel), expected)
        }
    }

    @Test func redAndGreenBecomeHardToTellApartWithDeuteranopia() throws {
        // The point of it: a red and a green of like lightness end up close in hue.
        let transform = try transform(.deuteranopia, Self.sRGB)
        let red = transform.apply([200, 60, 50])
        let green = transform.apply([90, 150, 50])
        let before = abs(200 - 90) + abs(60 - 150)
        let after = abs(Int(red[0]) - Int(green[0])) + abs(Int(red[1]) - Int(green[1]))
        #expect(after < before / 3)
    }

    // MARK: Modes

    @Test func theModesComeGroupedInMenuOrder() {
        let modes = ColorVisionMode.allCases
        #expect(
            modes.map(\.title) == [
                "Protanopia", "Protanomaly", "Deuteranopia", "Deuteranomaly", "Tritanopia", "Grayscale",
            ])
        #expect(modes.map(\.group) == [0, 0, 0, 0, 1, 2])
    }

    @Test func eachModeSaysWhoSeesThatWay() {
        #expect(ColorVisionMode.deuteranomaly.detail == "Weak green · about 5 in 100 men, the most common")
        #expect(ColorVisionMode.tritanopia.detail == "No blue cones · under 1 in 10,000 people")
        #expect(ColorVisionMode.allCases.allSatisfy { !$0.detail.isEmpty })
    }

    @Test func theIndicatorNamesTheMode() {
        #expect(ColorVisionMode.deuteranopia.indicatorLabel == "Deuteranopia · simulated")
    }

    @Test func aModeIsSavedByItsName() throws {
        let data = try JSONEncoder().encode(ColorVisionMode.tritanopia)
        #expect(String(data: data, encoding: .utf8) == "\"tritanopia\"")
        #expect(try JSONDecoder().decode(ColorVisionMode.self, from: data) == .tritanopia)
    }
}

struct ColorVisionChoiceTests {
    @Test func theEyeButtonTurnsTheChosenModeOnAndOff() {
        let off = ColorVisionChoice(mode: .protanopia, isOn: false)
        #expect(off.toggled() == ColorVisionChoice(mode: .protanopia, isOn: true))
        #expect(off.toggled().toggled() == off)
    }

    @Test func choosingAModeTurnsItOn() {
        let off = ColorVisionChoice(mode: .protanopia, isOn: false)
        #expect(off.turnedOn(.tritanopia) == ColorVisionChoice(mode: .tritanopia, isOn: true))
        let on = ColorVisionChoice(mode: .greyscale, isOn: true)
        #expect(on.turnedOn(.deuteranomaly) == ColorVisionChoice(mode: .deuteranomaly, isOn: true))
        #expect(on.turnedOn(.greyscale) == on)
    }

    @Test func nothingIsSimulatedWhileOff() {
        #expect(ColorVisionChoice(mode: .deuteranopia, isOn: false).active == nil)
        #expect(ColorVisionChoice(mode: .deuteranopia, isOn: true).active == .deuteranopia)
    }
}
