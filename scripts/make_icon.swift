#!/usr/bin/env swift

import AppKit
import Foundation

// Draws the SpaceCrunch app icon at 1024×1024 and writes it to the path given
// as the first argument (defaults to assets/icon_1024.png).

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/icon_1024.png"
let side: CGFloat = 1024
let canvas = NSRect(x: 0, y: 0, width: side, height: side)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side),
    pixelsHigh: Int(side),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap")
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create graphics context")
}
NSGraphicsContext.current = context
context.imageInterpolation = .high

// Transparent canvas.
NSColor.clear.setFill()
canvas.fill()

// macOS icon grid: 824×824 artwork centered on a 1024 canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 186
let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

// Soft drop shadow.
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 1.00, green: 0.47, blue: 0.32, alpha: 1),
    ending: NSColor(calibratedRed: 0.72, green: 0.08, blue: 0.22, alpha: 1)
)!
gradient.draw(in: tilePath, angle: -62)

NSGraphicsContext.restoreGraphicsState()

// Re-establish context without the shadow for details.
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

// Warm top-edge sheen. Use a full-height gradient so there is no hard seam.
NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
let sheen = NSGradient(colorsAndLocations:
    (NSColor.white.withAlphaComponent(0.0), 0.0),
    (NSColor.white.withAlphaComponent(0.0), 0.52),
    (NSColor.white.withAlphaComponent(0.22), 1.0)
)!
sheen.draw(in: tile, angle: 90)

// Faint concentric rings, suggesting a disk platter.
NSColor.white.withAlphaComponent(0.07).setStroke()
for inset in stride(from: CGFloat(0), through: 250, by: 62) {
    let ring = NSBezierPath(
        ovalIn: NSRect(
            x: tile.midX - 240 + inset / 2,
            y: tile.midY - 240 + inset / 2,
            width: 480 - inset,
            height: 480 - inset
        )
    )
    ring.lineWidth = 2
    ring.stroke()
}
NSGraphicsContext.restoreGraphicsState()

// Inner rim light.
tilePath.lineWidth = 3
NSColor.white.withAlphaComponent(0.22).setStroke()
tilePath.stroke()

// Drive symbol.
if let drive = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(0.96)]))
    if let tinted = drive.withSymbolConfiguration(config) {
        let driveSize = tinted.size
        let width: CGFloat = 470
        let height = width * (driveSize.height / max(driveSize.width, 1))
        let rect = NSRect(
            x: tile.midX - width / 2,
            y: tile.midY - height / 2 - 10,
            width: width,
            height: height
        )
        tinted.draw(in: rect)
    }
}

// Sparkles: the "crunch" that frees up space.
if let sparkle = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 170, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(0.92)]))
    if let tinted = sparkle.withSymbolConfiguration(config) {
        let size = tinted.size
        let width: CGFloat = 190
        let height = width * (size.height / max(size.width, 1))
        tinted.draw(
            in: NSRect(x: tile.maxX - width - 96, y: tile.maxY - height - 92, width: width, height: height)
        )
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: url)
print("Wrote \(url.path)")
