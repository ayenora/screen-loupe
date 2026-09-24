#!/usr/bin/env swift
// Draws the app icon and writes the macOS AppIcon set.
//
//   swift scripts/make_icon.swift ScreenLoupe/Resources/Assets.xcassets/AppIcon.appiconset [A|B]
//
// B, the default and the icon in use, is the mockup's "frame → viewer": a small capture frame and a
// large window with its magnified pixels, joined by callout lines. A is "loupe on graphite", kept so
// the choice can be revisited. Every size is drawn from the vector description, not downscaled from
// 1024 px. Coordinates are on Apple's 1024 icon grid with a top-left origin, as in the mockup.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The magnified pixels: a small blue button with white text pixels on a light UI.
let pixelArt: [[UInt32]] = {
    let b: UInt32 = 0x0A6FE0, w: UInt32 = 0xFFFFFF, l: UInt32 = 0xEEF1F5, g: UInt32 = 0xC9D1DB
    return [[l, l, l, g, l], [l, b, b, b, l], [b, w, b, w, b], [l, b, b, b, l], [l, l, g, l, l]]
}()

func drawPixels(in ctx: CGContext, origin: CGPoint, cell: CGFloat, gap: CGFloat) {
    for (row, colors) in pixelArt.enumerated() {
        for (column, hex) in colors.enumerated() {
            ctx.setFillColor(color(hex))
            ctx.fill(
                CGRect(
                    x: origin.x + CGFloat(column) * cell, y: origin.y + CGFloat(row) * cell, width: cell - gap,
                    height: cell - gap))
        }
    }
}

/// The squircle body with a vertical gradient and a soft drop shadow.
func drawBody(in ctx: CGContext, top: UInt32, bottom: UInt32) {
    let body = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185,
        transform: nil)
    ctx.saveGState()
    // Shadow offsets are in device space (y up): negative y falls downwards.
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(body)
    ctx.setFillColor(color(bottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()
}

/// B: frame → viewer.
func drawFrameToViewer(in ctx: CGContext) {
    drawBody(in: ctx, top: 0x2E95FF, bottom: 0x0050B8)

    // Callout lines from the frame's corners to the viewer's.
    ctx.setStrokeColor(color(0xFFFFFF, 0.45))
    ctx.setLineWidth(10)
    ctx.strokeLineSegments(between: [
        CGPoint(x: 210, y: 250), CGPoint(x: 400, y: 392),
        CGPoint(x: 370, y: 360), CGPoint(x: 820, y: 392),
        CGPoint(x: 210, y: 360), CGPoint(x: 400, y: 820),
    ])

    // The viewer with the magnified pixels.
    ctx.addPath(
        CGPath(
            roundedRect: CGRect(x: 400, y: 392, width: 420, height: 428), cornerWidth: 38, cornerHeight: 38,
            transform: nil))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    drawPixels(in: ctx, origin: CGPoint(x: 430, y: 424), cell: 74, gap: 4)

    // The capture frame and its corner handles.
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(14)
    ctx.stroke(CGRect(x: 206, y: 246, width: 168, height: 118))
    ctx.setFillColor(color(0xFFFFFF))
    for corner in [CGPoint(x: 206, y: 246), CGPoint(x: 374, y: 246), CGPoint(x: 206, y: 364), CGPoint(x: 374, y: 364)] {
        ctx.fill(CGRect(x: corner.x - 12, y: corner.y - 12, width: 24, height: 24))
    }
}

/// A: loupe on graphite.
func drawLoupe(in ctx: CGContext) {
    drawBody(in: ctx, top: 0x3A3F47, bottom: 0x16181C)

    let center = CGPoint(x: 452, y: 452)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - 214, y: center.y - 214, width: 428, height: 428))
    ctx.clip()
    ctx.setFillColor(color(0xEEF1F5))
    ctx.fill(CGRect(x: 230, y: 230, width: 444, height: 444))
    drawPixels(in: ctx, origin: CGPoint(x: 222, y: 222), cell: 92, gap: 4)
    ctx.restoreGState()

    ctx.setStrokeColor(color(0xE4E8EE))
    ctx.setLineWidth(36)
    ctx.strokeEllipse(in: CGRect(x: center.x - 232, y: center.y - 232, width: 464, height: 464))

    ctx.setLineCap(.round)
    ctx.setLineWidth(78)
    ctx.setStrokeColor(color(0xAEB5BF))
    ctx.strokeLineSegments(between: [CGPoint(x: 625, y: 625), CGPoint(x: 790, y: 790)])
    ctx.setStrokeColor(color(0xE4E8EE))
    ctx.strokeLineSegments(between: [CGPoint(x: 640, y: 640), CGPoint(x: 700, y: 700)])
}

func renderPNG(pixels: Int, variant: String, to url: URL) throws {
    guard
        let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw NSError(domain: "icon", code: 1) }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    // Top-left origin, y down, like the mockup's SVG.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    if variant == "A" { drawLoupe(in: ctx) } else { drawFrameToViewer(in: ctx) }
    guard let image = ctx.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "icon", code: 2) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 3) }
}

// The macOS AppIcon slots: point size × scale.
let slots: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3 else {
    FileHandle.standardError.write("usage: make_icon.swift <AppIcon.appiconset directory> [A|B]\n".data(using: .utf8)!)
    exit(1)
}
let variant = arguments.count == 3 ? arguments[2].uppercased() : "B"
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

var images: [[String: String]] = []
for slot in slots {
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    try renderPNG(pixels: slot.points * slot.scale, variant: variant, to: directory.appendingPathComponent(name))
    images.append([
        "filename": name, "idiom": "mac", "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appendingPathComponent("Contents.json"))
print("Wrote \(slots.count) icons (variant \(variant)) to \(directory.path)")
