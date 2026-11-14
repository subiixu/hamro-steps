#!/usr/bin/env swift
// Run from the repository root: swift design/logo/build.swift
// Export the selected production assets only: swift design/logo/build.swift --app-assets
// Native macOS only; no installed packages. SVGs are the geometry source.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let names = ["homeward", "shared-stride", "open-embrace"]
let titles = ["Homeward", "Shared Stride", "Open Embrace"]
let subtitles = ["Every walk brings us home.", "Small steps. One shared direction.", "A little closer, every day."]
let ink = "#282824"

func color(_ hex: String) -> NSColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255,
                   green: CGFloat((n >> 8) & 255) / 255,
                   blue: CGFloat(n & 255) / 255, alpha: 1)
}
struct Shape { let kind: String; let attrs: [String: String] }
final class SVG: NSObject, XMLParserDelegate {
    var shapes: [Shape] = []
    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if ["rect", "path"].contains(name) { shapes.append(Shape(kind: name, attrs: attributes)) }
        else { precondition(["svg", "title", "desc"].contains(name), "Unsupported SVG element") }
    }
}
func path(_ data: String) -> CGPath {
    let tokens = data.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    let p = CGMutablePath()
    var i = 0
    func point() -> CGPoint {
        let result = CGPoint(x: Double(tokens[i])!, y: Double(tokens[i + 1])!)
        i += 2
        return result
    }
    while i < tokens.count {
        let command = tokens[i]; i += 1
        switch command {
        case "M": p.move(to: point())
        case "L": p.addLine(to: point())
        case "C":
            let a = point(), b = point(), c = point()
            p.addCurve(to: c, control1: a, control2: b)
        case "Z": p.closeSubpath()
        default: fatalError("Unsupported path command: \(command)")
        }
    }
    return p
}
func bitmap(_ w: Int, _ h: Int, opaque: Bool = false, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}
func place(_ image: CGImage, _ rect: CGRect, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}
func save(_ image: CGImage, _ filename: String) {
    let url = root.appendingPathComponent(filename)
    let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, image, nil)
    precondition(CGImageDestinationFinalize(output))
    print("\(filename): \(image.width) × \(image.height)")
}
func rect(_ ctx: CGContext, _ r: CGRect, _ fill: String, _ radius: CGFloat = 0) {
    ctx.setFillColor(color(fill).cgColor)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          _ fill: String = "#282824", _ weight: NSFont.Weight = .regular) {
    (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(fill)
    ])
}
func masked(_ image: CGImage, _ r: CGRect, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.width * 0.225,
                      cornerHeight: r.height * 0.225, transform: nil))
    ctx.clip(); place(image, r, ctx); ctx.restoreGState()
}
// Keep the phase-one concept exports unchanged unless explicitly rebuilding them.
if CommandLine.arguments.contains("--app-assets") {
    let source = SVG()
    let parser = XMLParser(contentsOf: root.appendingPathComponent("shared-stride.svg"))!
    parser.delegate = source
    precondition(parser.parse())
    let marks = source.shapes.filter { $0.kind == "path" }
    precondition(marks.count == 1, "Shared Stride must have one continuous path")
    let geometry = marks[0].attrs["d"]!
    let appIcon = "../../ios/HamroSteps/Resources/Assets.xcassets/AppIcon.appiconset/"
    let outputs: [(String, Int, String, String)] = [
        (appIcon + "AppIcon-1024.png", 1024, "#E2672F", "#FFFFFF"),
        (appIcon + "AppIcon-1024-dark.png", 1024, "#2A1A12", "#F07A43"),
        (appIcon + "AppIcon-1024-tinted.png", 1024, "#000000", "#DDDDDD"),
        ("../../web/favicon.png", 64, "#E2672F", "#FFFFFF"),
        ("../../web/apple-touch-icon.png", 180, "#E2672F", "#FFFFFF")
    ]
    for (filename, size, background, foreground) in outputs {
        let large = bitmap(4096, 4096, opaque: true) { ctx in
            ctx.scaleBy(x: 4, y: 4)
            rect(ctx, CGRect(x: 0, y: 0, width: 1024, height: 1024), background)
            ctx.setFillColor(color(foreground).cgColor)
            ctx.addPath(path(geometry)); ctx.fillPath()
        }
        save(bitmap(size, size, opaque: true) {
            place(large, CGRect(x: 0, y: 0, width: size, height: size), $0)
        }, filename)
    }
    let assets = root.appendingPathComponent("../../ios/Shared/SharedAssets.xcassets/Icons")
    let logo = assets.appendingPathComponent("icon-logo.imageset")
    try FileManager.default.createDirectory(at: logo, withIntermediateDirectories: true)
    // A square viewBox around the path avoids doubling the hero's existing padding.
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="158 138 708 708">
      <path fill="#FFFFFF" d="\(geometry)"/>
    </svg>

    """
    try svg.write(to: logo.appendingPathComponent("icon-logo.svg"), atomically: true, encoding: .utf8)
    let manifest = try String(contentsOf: assets.appendingPathComponent("icon-home.imageset/Contents.json"), encoding: .utf8)
    try manifest.replacingOccurrences(of: "icon-home.svg", with: "icon-logo.svg")
        .write(to: logo.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("icon-logo.imageset: white template SVG, original Shared Stride geometry")
    exit(0)
}

var icons: [CGImage] = []
var previews: [CGImage] = []
var small: [CGImage] = []
for name in names {
    let source = SVG()
    let parser = XMLParser(contentsOf: root.appendingPathComponent(name + ".svg"))!
    parser.delegate = source
    precondition(parser.parse() && !source.shapes.isEmpty)
    let large = bitmap(4096, 4096) { ctx in
        ctx.scaleBy(x: 4, y: 4)
        for shape in source.shapes {
            let a = shape.attrs
            ctx.setFillColor(color(a["fill"]!).cgColor)
            if shape.kind == "path" { ctx.addPath(path(a["d"]!)); ctx.fillPath() }
            else {
                ctx.fill(CGRect(x: Double(a["x"]!)!, y: Double(a["y"]!)!,
                                width: Double(a["width"]!)!, height: Double(a["height"]!)!))
            }
        }
    }
    func scaled(_ n: Int) -> CGImage {
        bitmap(n, n) { place(large, CGRect(x: 0, y: 0, width: n, height: n), $0) }
    }
    let icon = scaled(1024), preview = scaled(180)
    icons.append(icon); previews.append(preview); small.append(scaled(60))
    save(icon, name + "-1024.png"); save(preview, name + "-180.png")
}

// Schematic home screen: original neutral placeholder tiles, no third-party marks.
// 390 × 844 logical points, exported at 3×. Hamro Steps uses a 60-point icon.
var phones: [CGImage] = []
for i in 0..<3 {
    let phone = bitmap(1170, 2532) { ctx in
        ctx.scaleBy(x: 3, y: 3)
        rect(ctx, CGRect(x: 0, y: 0, width: 390, height: 844), "#202321", 51)
        rect(ctx, CGRect(x: 7, y: 7, width: 376, height: 830), "#E6E7E0", 45)
        rect(ctx, CGRect(x: 137, y: 20, width: 116, height: 29), "#202321", 15)
        text("9:41", 30, 25, 14, ink, .semibold)
        text("100%", 319, 28, 11, ink, .medium)
        text("Sunday, 15 November", 32, 92, 16, ink, .medium)
        text("A good day to walk.", 32, 120, 26, ink, .semibold)
        rect(ctx, CGRect(x: 30, y: 180, width: 330, height: 138), "#F9F9F5", 26)
        text("TODAY", 50, 198, 10, "#66695E", .bold)
        text("Make time for each other.", 50, 226, 19, ink, .medium)
        text("One small walk is a start.", 50, 259, 14, "#66695E")
        let labels = ["Calendar", "Photos", "Notes", "Clock", "Weather", "Hamro Steps", "Maps", "Settings"]
        let fills = ["#C8BEB3", "#B9C5BB", "#D2C6A3", "#BAC2CA", "#BBCDD1", "#FFFFFF", "#C6CFB7", "#C1C1C2"]
        for j in 0..<8 {
            let x = CGFloat(30 + (j % 4) * 90), y = CGFloat(355 + (j / 4) * 108)
            if j == 5 { masked(icons[i], CGRect(x: x, y: y, width: 60, height: 60), ctx) }
            else { rect(ctx, CGRect(x: x, y: y, width: 60, height: 60), fills[j], 14) }
            let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
            let width = (labels[j] as NSString).size(withAttributes: [.font: font]).width
            text(labels[j], x + (60 - width) / 2, y + 67, 10.5, ink, .medium)
        }
        rect(ctx, CGRect(x: 180, y: 688, width: 6, height: 6), "#474C42", 3)
        rect(ctx, CGRect(x: 195, y: 688, width: 6, height: 6), "#B5BAB0", 3)
        rect(ctx, CGRect(x: 24, y: 725, width: 342, height: 84), "#F5F6F0", 27)
        for j in 0..<4 {
            rect(ctx, CGRect(x: 39 + j * 86, y: 737, width: 60, height: 60), "#CCD2C6", 14)
        }
        rect(ctx, CGRect(x: 134, y: 822, width: 122, height: 4), "#202321", 2)
    }
    phones.append(phone); save(phone, names[i] + "-home-screen.png")
}

// The three source-size rows use exact pixel dimensions; do not rescale the sheet.
let board = bitmap(3408, 2930) { ctx in
    rect(ctx, CGRect(x: 0, y: 0, width: 3408, height: 2930), "#F4F4F6")
    text("HAMRO STEPS  /  APP ICON EXPLORATIONS", 72, 36, 23, "#B5481B", .semibold)
    text("Three ways to say ‘we walk together’.", 72, 80, 48, ink, .semibold)
    text("PHASE 01   ·   LIGHT APPEARANCE   ·   15 NOV 2026", 2550, 102, 20, "#666666", .medium)
    for i in 0..<3 {
        let x = CGFloat(72 + i * 1104)
        text(String(format: "%02d", i + 1) + "  /  " + titles[i], x, 177, 34, ink, .semibold)
        text(subtitles[i], x, 227, 23, "#666666")
        place(icons[i], CGRect(x: x, y: 284, width: 1024, height: 1024), ctx)
        text("1024 × 1024  /  SQUARE SOURCE", x, 1332, 18, "#666666", .medium)
        text("180 × 180  /  HOME-SCREEN MASK", x, 1401, 18, "#666666", .medium)
        masked(previews[i], CGRect(x: x, y: 1443, width: 180, height: 180), ctx)
        text("60 × 60  /  ACTUAL PIXELS", x, 1660, 18, "#666666", .medium)
        masked(small[i], CGRect(x: x, y: 1702, width: 60, height: 60), ctx)
        text("ON A PHONE  /  60-POINT APP TILE", x, 1820, 18, "#666666", .medium)
        place(phones[i], CGRect(x: x, y: 1868, width: 390, height: 844), ctx)
        text(i == 0 ? "RECOMMENDED" : (i == 1 ? "MOST DIRECT" : "MOST EMOTIONAL"), x + 430, 1890, 18, "#B5481B", .semibold)
        let notes = [
            "An open path leads home.\nWarm, clear, easy to find.\nConnects walking and family.",
            "A shared climb, one step at a time.\nStrongest orange presence.\nMore movement than family.",
            "Two sides form one embrace.\nA caring, welcoming silhouette.\nLess specific to walking."
        ]
        for (j, line) in notes[i].split(separator: "\n").enumerated() {
            text(String(line), x + 430, CGFloat(1935 + j * 36), 22, "#666666")
        }
    }
    text("Original vector concepts · Phone views are schematic; surrounding apps use neutral placeholders.", 72, 2790, 23, "#666666")
    text("Inspect at 100% zoom to judge the 60 px row. Rounded masks are previews; exported icon files remain square.", 72, 2832, 23, "#666666")
}
save(board, "compare.png")
