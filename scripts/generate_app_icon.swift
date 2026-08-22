import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
let root = URL(fileURLWithPath: outputPath)
let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconImage {
    let filename: String
    let pixels: Int
}

let images = [
    IconImage(filename: "icon_16x16.png", pixels: 16),
    IconImage(filename: "icon_16x16@2x.png", pixels: 32),
    IconImage(filename: "icon_32x32.png", pixels: 32),
    IconImage(filename: "icon_32x32@2x.png", pixels: 64),
    IconImage(filename: "icon_128x128.png", pixels: 128),
    IconImage(filename: "icon_128x128@2x.png", pixels: 256),
    IconImage(filename: "icon_256x256.png", pixels: 256),
    IconImage(filename: "icon_256x256@2x.png", pixels: 512),
    IconImage(filename: "icon_512x512.png", pixels: 512),
    IconImage(filename: "icon_512x512@2x.png", pixels: 1024)
]

func drawIcon(size: Int) -> NSImage {
    let canvas = CGFloat(size)
    let image = NSImage(size: NSSize(width: canvas, height: canvas))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let radius = canvas * 0.223
    let basePath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    basePath.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.08, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.035, blue: 0.04, alpha: 1)
    ])
    background?.draw(in: bounds, angle: -35)

    let glowPath = NSBezierPath(ovalIn: CGRect(
        x: canvas * 0.12,
        y: canvas * 0.56,
        width: canvas * 0.78,
        height: canvas * 0.36
    ))
    NSColor(calibratedRed: 0.72, green: 0.88, blue: 1.0, alpha: 0.10).setFill()
    glowPath.fill()

    let tileRect = CGRect(
        x: canvas * 0.23,
        y: canvas * 0.21,
        width: canvas * 0.54,
        height: canvas * 0.58
    )
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: canvas * 0.08, yRadius: canvas * 0.08)
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
    tilePath.fill()
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setStroke()
    tilePath.lineWidth = max(1, canvas * 0.008)
    tilePath.stroke()

    let speakerBody = NSBezierPath()
    speakerBody.move(to: CGPoint(x: canvas * 0.36, y: canvas * 0.48))
    speakerBody.line(to: CGPoint(x: canvas * 0.45, y: canvas * 0.48))
    speakerBody.line(to: CGPoint(x: canvas * 0.58, y: canvas * 0.36))
    speakerBody.line(to: CGPoint(x: canvas * 0.58, y: canvas * 0.64))
    speakerBody.line(to: CGPoint(x: canvas * 0.45, y: canvas * 0.52))
    speakerBody.line(to: CGPoint(x: canvas * 0.36, y: canvas * 0.52))
    speakerBody.close()
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    speakerBody.fill()

    func strokeArc(rect: CGRect, start: CGFloat, end: CGFloat, alpha: CGFloat, width: CGFloat) {
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: start,
            endAngle: end
        )
        NSColor(calibratedWhite: 0.92, alpha: alpha).setStroke()
        arc.lineWidth = width
        arc.lineCapStyle = .round
        arc.stroke()
    }

    strokeArc(
        rect: CGRect(x: canvas * 0.42, y: canvas * 0.34, width: canvas * 0.32, height: canvas * 0.32),
        start: -38,
        end: 38,
        alpha: 0.95,
        width: max(2, canvas * 0.035)
    )
    strokeArc(
        rect: CGRect(x: canvas * 0.38, y: canvas * 0.26, width: canvas * 0.48, height: canvas * 0.48),
        start: -32,
        end: 32,
        alpha: 0.42,
        width: max(1, canvas * 0.018)
    )

    let barColor = NSColor(calibratedRed: 0.68, green: 0.82, blue: 0.92, alpha: 0.65)
    for index in 0..<3 {
        let y = canvas * (0.69 + CGFloat(index) * 0.035)
        let width = canvas * (0.22 - CGFloat(index) * 0.025)
        let rect = CGRect(x: canvas * 0.39, y: y, width: width, height: max(2, canvas * 0.015))
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        barColor.setFill()
        path.fill()
    }

    let shine = NSBezierPath(roundedRect: CGRect(
        x: canvas * 0.10,
        y: canvas * 0.68,
        width: canvas * 0.80,
        height: canvas * 0.20
    ), xRadius: canvas * 0.10, yRadius: canvas * 0.10)
    NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
    shine.fill()

    return image
}

for icon in images {
    let image = drawIcon(size: icon.pixels)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 1)
    }

    try png.write(to: iconsetURL.appendingPathComponent(icon.filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    resourcesURL.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "AppIcon", code: Int(process.terminationStatus))
}

print("Generated Resources/AppIcon.icns")
