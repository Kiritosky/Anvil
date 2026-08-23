#!/usr/bin/env swift

// Draws Anvil's app icon into Resources/Assets.xcassets/AppIcon.appiconset.
//
// Code rather than a design file on purpose: the icon is a handful of shapes,
// it has to exist in ten sizes, and a design file nobody can diff is how icons
// quietly drift out of date. The rendered PNGs are checked in because Xcode
// needs them at build time; this script is what regenerates them.
//
//     swift Scripts/make-icon.swift [ziel.appiconset]

import AppKit
import Foundation

// MARK: - Colours

/// Dark steel, with the warmth of a forge underneath.
let backgroundTop = NSColor(srgbRed: 0.24, green: 0.26, blue: 0.31, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)
let emberColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.11, alpha: 1)
let anvilColor = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)

// MARK: - Shapes

/// The anvil, in a 100 × 100 space with the origin at the top left.
///
/// A silhouette rather than a drawing: at 16 points nothing else survives, and
/// an icon that only works at 512 is a wallpaper.
func anvilPath(in size: CGFloat) -> NSBezierPath {
    let scale = size / 100
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        // AppKit draws from the bottom up; the design is written top-down.
        NSPoint(x: x * scale, y: (100 - y) * scale)
    }

    let path = NSBezierPath()
    // Top face, left to right, with the horn pulled out to the left.
    path.move(to: point(20, 30))
    path.line(to: point(84, 30))
    path.line(to: point(84, 41))
    path.line(to: point(66, 41))
    // Shoulder down into the waist.
    path.line(to: point(60, 50))
    path.line(to: point(60, 66))
    // Base, flared.
    path.line(to: point(76, 70))
    path.line(to: point(78, 80))
    path.line(to: point(22, 80))
    path.line(to: point(24, 70))
    path.line(to: point(40, 66))
    path.line(to: point(40, 50))
    path.line(to: point(34, 41))
    path.line(to: point(20, 41))
    // The horn: a wedge reaching past the body.
    path.line(to: point(6, 36))
    path.close()
    return path
}

/// The rounded square macOS expects, at Apple's proportions.
func backgroundPath(in size: CGFloat) -> NSBezierPath {
    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    return NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
}

// MARK: - Rendering

/// Draws at exact pixel dimensions. Going through `NSImage.lockFocus` would
/// pick up the display's backing scale and silently double every icon.
func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let background = backgroundPath(in: size)
    background.addClip()
    NSGradient(starting: backgroundTop, ending: backgroundBottom)?
        .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

    // The forge glow, low and off-centre so the shape does not look flat.
    let glowRadius = size * 0.55
    let glow = NSGradient(
        colors: [emberColor.withAlphaComponent(0.55), emberColor.withAlphaComponent(0)]
    )
    glow?.draw(
        fromCenter: NSPoint(x: size * 0.5, y: size * 0.18),
        radius: 0,
        toCenter: NSPoint(x: size * 0.5, y: size * 0.18),
        radius: glowRadius,
        options: []
    )

    // The anvil itself, with a hot top face.
    let anvil = anvilPath(in: size)
    anvilColor.set()
    anvil.fill()

    anvil.addClip()
    let faceHeight = size * 0.12
    NSGradient(
        starting: emberColor,
        ending: emberColor.withAlphaComponent(0)
    )?.draw(
        in: NSRect(x: 0, y: size - size * 0.41, width: size, height: faceHeight),
        angle: 90
    )

    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1)
    }
    try data.write(to: url)
}

// MARK: - Main

let iconset = URL(filePath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets.xcassets/AppIcon.appiconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try writePNG(renderIcon(size: CGFloat(base * scale)), to: iconset.appending(path: name))
        images.append([
            "idiom": "mac",
            "size": "\(base)x\(base)",
            "scale": "\(scale)x",
            "filename": name
        ])
    }
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"]
]
try JSONSerialization
    .data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appending(path: "Contents.json"))

print("Icon geschrieben: \(iconset.path(percentEncoded: false))")
