#!/usr/bin/env swift
// Run: swift design/app-icon/build.swift
// Dependency-free exporter for AppIcon.svg's rect, circle, and M/C/Z path primitives.
// The SVG is the geometry source. Every appearance uses the same antialiased mask.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Shape {
    let element: String
    let attributes: [String: String]
}

final class Source: NSObject, XMLParserDelegate {
    var shapes: [Shape] = []
    var unsupported: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if ["rect", "circle", "path"].contains(elementName) {
            shapes.append(Shape(element: elementName, attributes: attributes))
        } else if !["svg", "title", "desc"].contains(elementName) {
            unsupported.append(elementName)
        }
    }
}

func number(_ attributes: [String: String], _ name: String) -> CGFloat {
    guard let value = attributes[name], let result = Double(value) else {
        fatalError("Missing numeric SVG attribute: \(name)")
    }
    return CGFloat(result)
}

func path(_ data: String) -> CGPath {
    let tokens = data.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    let result = CGMutablePath()
    var index = 0
    func point() -> CGPoint {
        guard index + 1 < tokens.count,
              let x = Double(tokens[index]), let y = Double(tokens[index + 1]) else {
            fatalError("Invalid SVG path coordinate")
        }
        index += 2
        return CGPoint(x: x, y: y)
    }
    while index < tokens.count {
        let command = tokens[index]
        index += 1
        switch command {
        case "M": result.move(to: point())
        case "C":
            let first = point(), second = point(), end = point()
            result.addCurve(to: end, control1: first, control2: second)
        case "Z": result.closeSubpath()
        default: fatalError("Unsupported SVG path command: \(command)")
        }
    }
    return result
}

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let source = Source()
let parser = XMLParser(contentsOf: directory.appendingPathComponent("AppIcon.svg"))!
parser.delegate = source
guard parser.parse(), source.unsupported.isEmpty,
      source.shapes.filter({ $0.element == "circle" }).count == 1,
      source.shapes.filter({ $0.element == "path" }).count == 3 else {
    fatalError("Expected one circular ring and three SVG footprint paths")
}

let size = 1024
let scale = 4
let highSize = size * scale
let graySpace = CGColorSpaceCreateDeviceGray()
let maskContext = CGContext(data: nil, width: highSize, height: highSize,
                            bitsPerComponent: 8, bytesPerRow: highSize,
                            space: graySpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
maskContext.setFillColor(gray: 0, alpha: 1)
maskContext.fill(CGRect(x: 0, y: 0, width: highSize, height: highSize))
// SVG coordinates run downward; Quartz's bitmap drawing coordinates run upward.
maskContext.translateBy(x: 0, y: CGFloat(highSize))
maskContext.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
maskContext.setFillColor(gray: 1, alpha: 1)
maskContext.setStrokeColor(gray: 1, alpha: 1)
for shape in source.shapes {
    let a = shape.attributes
    switch shape.element {
    case "circle":
        let radius = number(a, "r")
        maskContext.setLineWidth(number(a, "stroke-width"))
        maskContext.strokeEllipse(in: CGRect(x: number(a, "cx") - radius,
                                             y: number(a, "cy") - radius,
                                             width: radius * 2, height: radius * 2))
    case "path":
        maskContext.addPath(path(a["d"]!))
        maskContext.fillPath()
    default: break // Background is appearance-specific and must not enter the mask.
    }
}
let reduced = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: size,
                        space: graySpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
reduced.interpolationQuality = .high
reduced.draw(maskContext.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
let coverage = reduced.data!.assumingMemoryBound(to: UInt8.self)

func rgb(_ hex: String) -> [UInt8] {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return [UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
}

let lightBackground = source.shapes.first(where: { $0.element == "rect" })!.attributes["fill"]!
let lightForeground = source.shapes.first(where: { $0.element == "path" })!.attributes["fill"]!
let variants: [(String, String, String?)] = [
    ("AppIcon-1024.png", lightForeground, lightBackground),
    ("AppIcon-1024-dark.png", "#F07A43", "#2A1A12"),
    ("AppIcon-1024-tinted.png", "#DDDDDD", nil)
]
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
for (filename, foreground, background) in variants {
    let fg = rgb(foreground)
    let bg = background.map(rgb)
    let channels = bg == nil ? 4 : 3
    var pixels = [UInt8](repeating: 0, count: size * size * channels)
    for pixel in 0..<(size * size) {
        let alpha = Int(coverage[pixel])
        for channel in 0..<3 {
            if let bg {
                pixels[pixel * channels + channel] = UInt8(
                    (Int(fg[channel]) * alpha + Int(bg[channel]) * (255 - alpha) + 127) / 255)
            } else {
                // Straight alpha preserves neutral RGB even along antialiased edges.
                pixels[pixel * channels + channel] = alpha == 0 ? 0 : fg[channel]
            }
        }
        if bg == nil { pixels[pixel * channels + 3] = UInt8(alpha) }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let alphaInfo: CGImageAlphaInfo = bg == nil ? .last : .none
    let image = CGImage(width: size, height: size, bitsPerComponent: 8,
                        bitsPerPixel: channels * 8, bytesPerRow: size * channels,
                        space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false,
                        intent: .defaultIntent)!
    let output = directory.appendingPathComponent(filename)
    let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(filename)") }
    print("Exported \(filename): 1024×1024, \(background == nil ? "grayscale on transparent" : "opaque RGB"), \(foreground)\(background.map { " on " + $0 } ?? "")")
}
