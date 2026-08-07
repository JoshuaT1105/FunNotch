//
//  MakeIcon.swift
//  FunNotch build tool
//
//  Renders the app icon at every size iconutil expects. Run by build.sh with
//  the destination .iconset directory as its only argument.
//

import AppKit
import Foundation

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

/// The notch silhouette, matching the shape used in the app itself.
func notchPath(in rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - topRadius),
        control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.minY + bottomRadius))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.minY),
        control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.minY))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + bottomRadius),
        control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - topRadius))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.maxY),
        control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
    )
    path.closeSubpath()
    return path
}

func renderIcon(pixels: Int) -> Data? {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let scale = CGFloat(pixels) / 1024.0
    let full = CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))

    // Rounded-square backdrop with a subtle vertical gradient.
    let inset = 60 * scale
    let plate = full.insetBy(dx: inset, dy: inset)
    let plateRadius = 200 * scale
    let platePath = CGPath(
        roundedRect: plate,
        cornerWidth: plateRadius,
        cornerHeight: plateRadius,
        transform: nil
    )

    context.saveGState()
    context.addPath(platePath)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
            CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
    }
    context.restoreGState()

    // The notch itself, sitting against the top edge of the plate.
    let notchWidth = plate.width * 0.62
    let notchHeight = plate.height * 0.26
    let notch = CGRect(
        x: plate.midX - notchWidth / 2,
        y: plate.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight
    )
    context.addPath(notchPath(in: notch, topRadius: 26 * scale, bottomRadius: 64 * scale))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fillPath()

    // Spectrum bars below the notch, echoing the live activity.
    let barCount = 4
    let barWidth = 46 * scale
    let spacing = 30 * scale
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
    let heights: [CGFloat] = [0.45, 0.85, 0.6, 1.0]
    let maxBarHeight = plate.height * 0.30
    let baseY = plate.minY + plate.height * 0.20

    for index in 0 ..< barCount {
        let x = plate.midX - totalWidth / 2 + CGFloat(index) * (barWidth + spacing)
        let height = maxBarHeight * heights[index]
        let bar = CGRect(x: x, y: baseY, width: barWidth, height: height)
        context.addPath(CGPath(
            roundedRect: bar,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        ))
        context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 0.92))
        context.fillPath()
    }

    guard let image = context.makeImage() else { return nil }
    let representation = NSBitmapImageRep(cgImage: image)
    return representation.representation(using: .png, properties: [:])
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: makeicon <iconset directory>\n".data(using: .utf8)!)
    exit(1)
}

let destination = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

for entry in sizes {
    guard let data = renderIcon(pixels: entry.pixels) else { continue }
    try? data.write(to: destination.appendingPathComponent("\(entry.name).png"))
}
