#!/usr/bin/env swift
//
// Crops an icon's transparent margin away and refits the artwork to fill the canvas.
//
//   swift scripts/frame-icon.swift <in.png> <out.png> [canvas] [fill]
//
// Generated artwork tends to sit in the middle of its canvas with a wide transparent
// border, which in the Dock reads as a small icon with nothing around it. `sips` can
// only crop centred, and artwork is rarely centred — this one's visible pixels sit
// 16px above the canvas centre — so the crop has to be offset, which is what this
// does. Written as a script rather than a compiled tool so `scripts/bundle.sh` can
// call it with no build step of its own.
//
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: frame-icon.swift <in.png> <out.png> [canvas] [fill]\n".utf8))
    exit(2)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let canvas = arguments.count > 3 ? Int(arguments[3])! : 1024
/// How much of the canvas the artwork should span. 1.0 means edge to edge.
let fill = arguments.count > 4 ? Double(arguments[4])! : 1.0

guard let source = NSImage(contentsOf: inputURL),
      let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("frame-icon: cannot read \(inputURL.path)\n".utf8))
    exit(1)
}

let width = cgImage.width
let height = cgImage.height

// Redraw into a known layout rather than trusting the file's own channel order.
let colorSpace = CGColorSpaceCreateDeviceRGB()
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
}

// The visible bounds: anything not effectively transparent. The threshold is low so
// that a soft drop shadow counts as part of the artwork — cropping it off would leave
// the icon looking cut out.
let alphaThreshold: UInt8 = 8
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= alphaThreshold {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("frame-icon: image is fully transparent\n".utf8))
    exit(1)
}

let content = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = cgImage.cropping(to: content) else {
    FileHandle.standardError.write(Data("frame-icon: crop failed\n".utf8))
    exit(1)
}

// Fit, not fill: the aspect ratio is preserved and the result is centred, so a tall
// or wide piece of artwork keeps its proportions instead of being stretched.
let target = Double(canvas) * fill
let scale = min(target / content.width, target / content.height)
let drawn = CGSize(width: content.width * scale, height: content.height * scale)
let origin = CGPoint(x: (Double(canvas) - drawn.width) / 2,
                     y: (Double(canvas) - drawn.height) / 2)

let output = CGContext(data: nil, width: canvas, height: canvas,
                       bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
output.interpolationQuality = .high
output.draw(cropped, in: CGRect(origin: origin, size: drawn))

guard let framed = output.makeImage() else {
    FileHandle.standardError.write(Data("frame-icon: render failed\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: framed)
try! bitmap.representation(using: .png, properties: [:])!.write(to: outputURL)

let percent = Int(drawn.height / Double(canvas) * 100)
print("frame-icon: cropped \(width)x\(height) to \(Int(content.width))x\(Int(content.height))"
    + ", artwork now spans \(percent)% of a \(canvas)px canvas")
