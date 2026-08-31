#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-assets.swift <Resources directory>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

func bitmapContext(width: Int, height: Int) throws -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "TypelessPlusPlusAssets", code: 1)
    }
    return context
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TypelessPlusPlusAssets", code: 2)
    }
    try data.write(to: url)
}

func drawCenteredText(
    _ text: String,
    font: NSFont,
    color: NSColor,
    baselineY: CGFloat,
    width: CGFloat,
    context: CGContext
) {
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color,
        ]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetImageBounds(line, context)
    context.textPosition = CGPoint(x: (width - bounds.width) / 2, y: baselineY)
    CTLineDraw(line, context)
}

func makeAppIcon() throws -> CGImage {
    let side = 1024
    let context = try bitmapContext(width: side, height: side)
    let canvas = CGFloat(side)
    context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    let tile = CGRect(x: 72, y: 72, width: 880, height: 880)
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: 210,
        cornerHeight: 210,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -24),
        blur: 42,
        color: CGColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 0.42)
    )
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.07, green: 0.11, blue: 0.20, alpha: 1),
            CGColor(red: 0.12, green: 0.18, blue: 0.31, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 230, y: 850),
        end: CGPoint(x: 820, y: 150),
        options: []
    )
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    context.setLineWidth(4)
    context.strokePath()

    let barColor = CGColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.96)
    let barX: [CGFloat] = [300, 400, 500, 600, 700]
    let barHeight: [CGFloat] = [190, 320, 410, 280, 150]
    for (x, height) in zip(barX, barHeight) {
        let frame = CGRect(x: x, y: (canvas - height) / 2, width: 54, height: height)
        let path = CGPath(
            roundedRect: frame,
            cornerWidth: 27,
            cornerHeight: 27,
            transform: nil
        )
        context.addPath(path)
        context.setFillColor(barColor)
        context.fillPath()
    }

    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: 0.02, green: 0.05, blue: 0.10, alpha: 0.55))
    context.setLineWidth(104)
    context.move(to: CGPoint(x: 286, y: 276))
    context.addLine(to: CGPoint(x: 742, y: 748))
    context.strokePath()

    context.setStrokeColor(CGColor(red: 0.25, green: 0.92, blue: 0.78, alpha: 1))
    context.setLineWidth(72)
    context.move(to: CGPoint(x: 286, y: 276))
    context.addLine(to: CGPoint(x: 742, y: 748))
    context.strokePath()

    guard let image = context.makeImage() else {
        throw NSError(domain: "TypelessPlusPlusAssets", code: 3)
    }
    return image
}

func resizedImage(_ image: CGImage, side: Int) throws -> CGImage {
    let context = try bitmapContext(width: side, height: side)
    context.interpolationQuality = .high
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
    )
    guard let resized = context.makeImage() else {
        throw NSError(domain: "TypelessPlusPlusAssets", code: 4)
    }
    return resized
}

func makeDMGBackground() throws -> CGImage {
    let width = 660
    let height = 420
    let context = try bitmapContext(width: width, height: height)
    let canvasWidth = CGFloat(width)
    let canvasHeight = CGFloat(height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1),
            CGColor(red: 0.91, green: 0.92, blue: 0.95, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvasHeight),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    context.setStrokeColor(CGColor(red: 0.15, green: 0.18, blue: 0.24, alpha: 0.08))
    context.setLineWidth(2)
    context.stroke(CGRect(x: 1, y: 1, width: canvasWidth - 2, height: canvasHeight - 2))

    drawCenteredText(
        "Install Typeless++",
        font: .systemFont(ofSize: 24, weight: .semibold),
        color: NSColor(white: 0.14, alpha: 1),
        baselineY: 356,
        width: canvasWidth,
        context: context
    )
    drawCenteredText(
        "1. Drag Typeless++ into Applications",
        font: .systemFont(ofSize: 14, weight: .regular),
        color: NSColor(white: 0.39, alpha: 1),
        baselineY: 330,
        width: canvasWidth,
        context: context
    )
    drawCenteredText(
        "2. Open it from Applications",
        font: .systemFont(ofSize: 14, weight: .regular),
        color: NSColor(white: 0.39, alpha: 1),
        baselineY: 307,
        width: canvasWidth,
        context: context
    )

    let arrowColor = CGColor(red: 0.27, green: 0.31, blue: 0.40, alpha: 0.48)
    let arrowY: CGFloat = 195
    let startX: CGFloat = 252
    let endX: CGFloat = 398
    context.setStrokeColor(arrowColor)
    context.setFillColor(arrowColor)
    context.setLineWidth(5)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: startX, y: arrowY))
    context.addLine(to: CGPoint(x: endX, y: arrowY))
    context.strokePath()
    context.beginPath()
    context.move(to: CGPoint(x: endX + 18, y: arrowY))
    context.addLine(to: CGPoint(x: endX - 1, y: arrowY + 13))
    context.addLine(to: CGPoint(x: endX - 1, y: arrowY - 13))
    context.closePath()
    context.fillPath()

    guard let image = context.makeImage() else {
        throw NSError(domain: "TypelessPlusPlusAssets", code: 5)
    }
    return image
}

let masterIcon = try makeAppIcon()
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
if FileManager.default.fileExists(atPath: iconset.path) {
    try FileManager.default.removeItem(at: iconset)
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let iconVariants: [(String, Int)] = [
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
for (name, side) in iconVariants {
    try writePNG(
        resizedImage(masterIcon, side: side),
        to: iconset.appendingPathComponent(name)
    )
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path,
    iconset.path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "TypelessPlusPlusAssets", code: 6)
}
try FileManager.default.removeItem(at: iconset)

try writePNG(
    makeDMGBackground(),
    to: outputDirectory.appendingPathComponent("dmg-background.png")
)

print("Generated AppIcon.icns and dmg-background.png in \(outputDirectory.path)")
