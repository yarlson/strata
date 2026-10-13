// SPDX-License-Identifier: MIT
//
// Renders Strata's logo on the macOS icon tile into an .iconset folder.
// Usage: swift render-icon.swift <logo.svg> <output.iconset>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let logo = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <logo.svg> <output.iconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: 1
    )
}

func render(pixels: Int) throws -> Data {
    let canvas = CGFloat(pixels)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
    else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // The macOS icon grid: an 824/1024 tile with continuous corners.
    let inset = canvas * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let radius = tile.width * 0.225
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSGradient(colors: [color(0x0C293D), color(0x03111E)])?.draw(in: shape, angle: -90)
    color(0x2CCCEB).withAlphaComponent(0.35).setStroke()
    shape.lineWidth = max(1, canvas / 256)
    shape.stroke()
    let mark = tile.insetBy(dx: tile.width * 0.2, dy: tile.height * 0.2)
    let tinted = NSImage(size: logo.size, flipped: false) { rect in
        logo.draw(in: rect)
        color(0x2CCCEB).set()
        rect.fill(using: .sourceIn)
        return true
    }
    tinted.draw(in: mark, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let data = try render(pixels: points * scale)
        try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
