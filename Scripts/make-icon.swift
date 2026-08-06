#!/usr/bin/env swift

// Draws Anvil's app icon and writes AppIcon.icns.
//
// Code rather than a design file on purpose: the icon is a handful of shapes,
// it has to exist in seven sizes, and a checked-in binary nobody can diff is
// how icons quietly drift out of date. Run through Scripts/build-app.sh, or
// on its own:
//
//     swift Scripts/make-icon.swift .build/AppIcon.icns

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

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

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

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "make-icon", code: 1)
    }
    try data.write(to: url)
}

// MARK: - Main

let destination = URL(filePath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : ".build/AppIcon.icns")

let iconset = destination.deletingLastPathComponent().appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects, each in single and double resolution.
for base in [16, 32, 128, 256, 512] {
    try writePNG(
        renderIcon(size: CGFloat(base)),
        to: iconset.appending(path: "icon_\(base)x\(base).png")
    )
    try writePNG(
        renderIcon(size: CGFloat(base * 2)),
        to: iconset.appending(path: "icon_\(base)x\(base)@2x.png")
    )
}

let process = Process()
process.executableURL = URL(filePath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path(percentEncoded: false),
                     "-o", destination.path(percentEncoded: false)]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil ist fehlgeschlagen\n".utf8))
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
print("Icon geschrieben: \(destination.path(percentEncoded: false))")
