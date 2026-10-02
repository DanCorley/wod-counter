// Generates the three AppIcon variants (light, dark, tinted) as 1024x1024 PNGs.
//
// Run:  swift Tools/GenerateAppIcon.swift WODCounter/Assets.xcassets/AppIcon.appiconset
//
// The icon is a timer ring — a partly-filled progress arc with a stopwatch
// crown — wrapped around a barbell: rounds counted, time elapsed, weight moved.
// Everything is parameterised below so the palette can be changed without
// touching the drawing code.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

struct Palette {
    let backgroundTop: CGColor
    let backgroundBottom: CGColor
    let track: CGColor
    let arc: CGColor
    let glyph: CGColor
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

enum Variant: String, CaseIterable {
    case light = "AppIcon-Light"
    case dark = "AppIcon-Dark"
    case tinted = "AppIcon-Tinted"

    var palette: Palette {
        switch self {
        case .light:
            // Warm and high-effort, echoing the timer's orange controls.
            return Palette(
                backgroundTop: rgb(255, 138, 48),
                backgroundBottom: rgb(214, 40, 40),
                track: rgb(255, 255, 255, 0.24),
                arc: rgb(255, 255, 255),
                glyph: rgb(255, 255, 255)
            )
        case .dark:
            return Palette(
                backgroundTop: rgb(38, 20, 12),
                backgroundBottom: rgb(16, 10, 8),
                track: rgb(255, 255, 255, 0.14),
                arc: rgb(255, 138, 48),
                glyph: rgb(255, 196, 150)
            )
        case .tinted:
            // iOS derives the tint from luminance, so this variant is greyscale.
            return Palette(
                backgroundTop: rgb(0, 0, 0),
                backgroundBottom: rgb(0, 0, 0),
                track: rgb(255, 255, 255, 0.18),
                arc: rgb(255, 255, 255),
                glyph: rgb(235, 235, 235)
            )
        }
    }
}

// MARK: - Drawing

let side: CGFloat = 1024

func drawIcon(_ ctx: CGContext, _ palette: Palette) {
    let center = CGPoint(x: side / 2, y: side / 2)

    // Background. iOS masks the rounded corners itself, so this is full-bleed.
    ctx.saveGState()
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray,
                                 locations: [0, 1]) {
        ctx.addRect(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.clip()
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: side),
                               end: CGPoint(x: side, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    let ringRadius: CGFloat = 300
    let ringWidth: CGFloat = 80

    // Stopwatch crown. It has to clear the ring's outer edge (radius plus half
    // the stroke width), otherwise it overlaps the band and reads as a blob
    // rather than a crown; the small negative inset tucks it in just enough to
    // look attached.
    let crownWidth: CGFloat = 136
    let crownHeight: CGFloat = 76
    let crown = CGPath(
        roundedRect: CGRect(x: center.x - crownWidth / 2,
                            y: center.y + ringRadius + ringWidth / 2 - 14,
                            width: crownWidth,
                            height: crownHeight),
        cornerWidth: 32, cornerHeight: 32, transform: nil
    )
    ctx.addPath(crown)
    ctx.setFillColor(palette.glyph)
    ctx.fillPath()

    // Ring track.
    ctx.setLineWidth(ringWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(palette.track)
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Progress arc: starts at twelve o'clock, sweeps most of the way round.
    let start: CGFloat = .pi / 2
    let sweep: CGFloat = .pi * 2 * 0.72
    ctx.setStrokeColor(palette.arc)
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.strokePath()

    // Barbell: a bar with a plate at each end.
    let barHalf: CGFloat = 122
    let barThickness: CGFloat = 50
    ctx.setFillColor(palette.glyph)
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: center.x - barHalf, y: center.y - barThickness / 2,
                            width: barHalf * 2, height: barThickness),
        cornerWidth: barThickness / 2, cornerHeight: barThickness / 2, transform: nil
    ))
    ctx.fillPath()

    let plateWidth: CGFloat = 56
    let plateHeight: CGFloat = 184
    for direction in [-1, 1] as [CGFloat] {
        let x = center.x + direction * (barHalf + plateWidth / 2) - plateWidth / 2
        ctx.addPath(CGPath(
            roundedRect: CGRect(x: x, y: center.y - plateHeight / 2,
                                width: plateWidth, height: plateHeight),
            cornerWidth: 22, cornerHeight: 22, transform: nil
        ))
    }
    ctx.fillPath()
}

// MARK: - Output

func render(_ variant: Variant, to directory: URL) throws {
    guard let ctx = CGContext(
        data: nil,
        width: Int(side), height: Int(side),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.contextFailed
    }

    drawIcon(ctx, variant.palette)

    guard let image = ctx.makeImage() else { throw IconError.imageFailed }

    let url = directory.appendingPathComponent("\(variant.rawValue).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw IconError.destinationFailed(url)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.writeFailed(url) }
    print("wrote \(url.lastPathComponent)")
}

enum IconError: Error {
    case contextFailed
    case imageFailed
    case destinationFailed(URL)
    case writeFailed(URL)
    case missingOutputDirectory
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else { throw IconError.missingOutputDirectory }
let outputDirectory = URL(fileURLWithPath: arguments[1])

for variant in Variant.allCases {
    try render(variant, to: outputDirectory)
}
