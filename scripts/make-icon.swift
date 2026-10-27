// Draws the HouseCleaning app icon and writes Assets/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Four-pointed sparkle with slightly curved sides.
func sparkle(center: CGPoint, radius: CGFloat) -> CGPath {
    let points = [
        CGPoint(x: center.x, y: center.y + radius),
        CGPoint(x: center.x + radius, y: center.y),
        CGPoint(x: center.x, y: center.y - radius),
        CGPoint(x: center.x - radius, y: center.y),
    ]
    let pinch = radius * 0.16
    let controls = [
        CGPoint(x: center.x + pinch, y: center.y + pinch),
        CGPoint(x: center.x + pinch, y: center.y - pinch),
        CGPoint(x: center.x - pinch, y: center.y - pinch),
        CGPoint(x: center.x - pinch, y: center.y + pinch),
    ]
    let path = CGMutablePath()
    path.move(to: points[0])
    for index in 0..<4 {
        path.addQuadCurve(to: points[(index + 1) % 4], control: controls[index])
    }
    path.closeSubpath()
    return path
}

/// Draws the icon on a 1024×1024 canvas (origin bottom-left).
func drawIcon(in context: CGContext) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // Background tile on the standard macOS icon grid (824pt body, 100pt margin).
    let tile = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 185,
        cornerHeight: 185,
        transform: nil
    )
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.3))
    context.addPath(tile)
    context.setFillColor(color(0x2F6FDB))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let sky = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x7FD8FF), color(0x2F6FDB)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Soft ground shadow under the house.
    context.setFillColor(color(0x0B3B8C, alpha: 0.25))
    context.fillEllipse(in: CGRect(x: 262, y: 222, width: 500, height: 70))
    context.restoreGState()

    // Chimney, behind the roof.
    context.setFillColor(color(0xE8524A))
    context.fill(CGRect(x: 620, y: 600, width: 64, height: 130))

    // Walls, including the gable under the roof.
    let walls = CGMutablePath()
    walls.move(to: CGPoint(x: 354, y: 255))
    walls.addLine(to: CGPoint(x: 670, y: 255))
    walls.addQuadCurve(to: CGPoint(x: 692, y: 277), control: CGPoint(x: 692, y: 255))
    walls.addLine(to: CGPoint(x: 692, y: 560))
    walls.addLine(to: CGPoint(x: 512, y: 725))
    walls.addLine(to: CGPoint(x: 332, y: 560))
    walls.addLine(to: CGPoint(x: 332, y: 277))
    walls.addQuadCurve(to: CGPoint(x: 354, y: 255), control: CGPoint(x: 332, y: 255))
    walls.closeSubpath()
    context.addPath(walls)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()

    // Roof.
    let roof = CGMutablePath()
    roof.move(to: CGPoint(x: 272, y: 525))
    roof.addLine(to: CGPoint(x: 512, y: 745))
    roof.addLine(to: CGPoint(x: 752, y: 525))
    context.addPath(roof)
    context.setStrokeColor(color(0xFF6B5B))
    context.setLineWidth(72)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    // Door and windows.
    let door = CGPath(
        roundedRect: CGRect(x: 467, y: 255, width: 90, height: 160),
        cornerWidth: 16,
        cornerHeight: 16,
        transform: nil
    )
    context.addPath(door)
    context.setFillColor(color(0x2F6FDB))
    context.fillPath()
    context.setFillColor(color(0xFFD60A))
    context.fillEllipse(in: CGRect(x: 535, y: 325, width: 12, height: 12))

    for x in [372.0, 587.0] {
        let window = CGPath(
            roundedRect: CGRect(x: x, y: 420, width: 65, height: 65),
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        context.addPath(window)
        context.setFillColor(color(0x7FD8FF))
        context.fillPath()
    }

    // Sparkles.
    context.setFillColor(color(0xFFD60A))
    context.addPath(sparkle(center: CGPoint(x: 775, y: 800), radius: 82))
    context.fillPath()
    context.addPath(sparkle(center: CGPoint(x: 850, y: 668), radius: 40))
    context.fillPath()
    context.setFillColor(color(0xFFFFFF, alpha: 0.95))
    context.addPath(sparkle(center: CGPoint(x: 240, y: 770), radius: 52))
    context.fillPath()
}

func renderPNG(pixels: Int, to url: URL) {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)

    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    renderPNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    renderPNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()

// Keep a full-size preview next to the icns for the README and quick review.
renderPNG(pixels: 1024, to: assets.appendingPathComponent("AppIcon.png"))
print("Wrote Assets/AppIcon.icns")
