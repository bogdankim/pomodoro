import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the app icon (orange rounded square, white progress ring, center dot)
// and writes an AppIcon.iconset, suitable for `iconutil -c icns`.

let workDir = URL(fileURLWithPath: "build/icon.iconset")
try? FileManager.default.removeItem(at: workDir)
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func renderIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Inset rounded square, as macOS icons keep a small transparent margin.
    let inset = s * 0.094
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let background = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(background)
    context.clip()

    let colors = [srgb(255, 161, 37), srgb(242, 107, 2)] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: s / 2, y: rect.maxY), end: CGPoint(x: s / 2, y: rect.minY), options: [])

    // Progress ring: starts at 12 o'clock, sweeps 270 degrees clockwise.
    let ringCenter = CGPoint(x: s / 2, y: s / 2)
    let ringRadius = s * 0.262
    let lineWidth = s * 0.082
    context.setStrokeColor(srgb(255, 255, 255))
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.addArc(
        center: ringCenter, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 - 1.5 * .pi,
        clockwise: true)
    context.strokePath()

    // Center dot.
    context.setFillColor(srgb(255, 255, 255))
    let dotRadius = s * 0.052
    context.fillEllipse(
        in: CGRect(
            x: ringCenter.x - dotRadius,
            y: ringCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to write \(url.path)")
    }
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in entries {
    // Render at 2x the target and downsample for crisp small sizes.
    let rendered = renderIcon(size: size)
    writePNG(rendered, to: workDir.appendingPathComponent(name))
    print("wrote \(name) (\(size)pt)")
}
