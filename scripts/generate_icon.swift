#!/usr/bin/env swift
//
// generate_icon.swift
// Takes a source icon PNG and applies Apple's macOS squircle mask,
// then exports all 10 required sizes for the AppIcon.appiconset.
//
// Usage: swift scripts/generate_icon.swift <source.png> <output_dir>
//
// The macOS icon shape is a "continuous corner" superellipse (squircle).
// Apple uses ~22.37% corner radius relative to icon size, with the
// smoothed continuous corner curve (not a simple arc).

import AppKit
import Foundation

// MARK: - Squircle Path

/// Creates an Apple-style continuous corner (squircle) path.
/// Uses a superellipse approximation: |x|^n + |y|^n = 1 with n ≈ 4.5
/// Then scaled and translated to fit the given rect.
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let w = rect.width
    let h = rect.height
    let cx = rect.midX
    let cy = rect.midY

    // Apple's macOS icon uses a continuous corner with ~22.37% radius.
    // A superellipse with n=5 closely approximates this shape.
    let n: CGFloat = 5.0
    let steps = 360

    for i in 0...steps {
        let angle = CGFloat(i) / CGFloat(steps) * 2.0 * .pi
        let cosA = cos(angle)
        let sinA = sin(angle)

        // Superellipse formula: x = a * sign(cos) * |cos|^(2/n)
        let x = cx + (w / 2.0) * sign(cosA) * pow(abs(cosA), 2.0 / n)
        let y = cy + (h / 2.0) * sign(sinA) * pow(abs(sinA), 2.0 / n)

        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func sign(_ v: CGFloat) -> CGFloat {
    if v > 0 { return 1 }
    if v < 0 { return -1 }
    return 0
}

// MARK: - Icon Generation

func generateIcon(source sourcePath: String, outputDir: String) throws {
    // Load source image
    guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
        fputs("Error: Cannot load image at \(sourcePath)\n", stderr)
        exit(1)
    }

    guard
        let sourceCG = sourceImage.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        )
    else {
        fputs("Error: Cannot get CGImage from source\n", stderr)
        exit(1)
    }

    let sourceSize = CGSize(
        width: CGFloat(sourceCG.width),
        height: CGFloat(sourceCG.height)
    )

    // macOS icon sizes: (points, scale, pixel size)
    let sizes: [(name: String, px: Int)] = [
        ("icon_16x16", 16),
        ("icon_32x32", 32),
        ("icon_64x64", 64),
        ("icon_128x128", 128),
        ("icon_256x256", 256),
        ("icon_512x512", 512),
        ("icon_1024x1024", 1024),
    ]

    let fm = FileManager.default
    if !fm.fileExists(atPath: outputDir) {
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    }

    for size in sizes {
        let px = size.px
        let rect = CGRect(x: 0, y: 0, width: px, height: px)

        // Inset slightly (~3.5%) to leave room for the icon to "breathe"
        // Apple's template has the squircle inset from the full canvas
        let insetFraction: CGFloat = 0.035
        let inset = CGFloat(px) * insetFraction
        let iconRect = rect.insetBy(dx: inset, dy: inset)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let ctx = CGContext(
                data: nil,
                width: px,
                height: px,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            fputs("Error: Cannot create CGContext for \(size.name)\n", stderr)
            continue
        }

        // Clear to transparent
        ctx.clear(rect)

        // Clip to squircle
        let mask = squirclePath(in: iconRect)
        ctx.addPath(mask)
        ctx.clip()

        // Draw the source image scaled to fill the squircle bounds.
        // The source has its own rounded corners with a green background,
        // so we draw it filling the icon rect — the squircle clip removes
        // whatever corners the source had and applies the correct shape.
        ctx.draw(sourceCG, in: iconRect)

        guard let outputCG = ctx.makeImage() else {
            fputs("Error: Cannot make image for \(size.name)\n", stderr)
            continue
        }

        let outputURL = URL(fileURLWithPath: outputDir)
            .appendingPathComponent("\(size.name).png")

        let rep = NSBitmapImageRep(cgImage: outputCG)
        rep.size = NSSize(width: px, height: px)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            fputs("Error: Cannot create PNG for \(size.name)\n", stderr)
            continue
        }

        try pngData.write(to: outputURL)
        print("  \(size.name).png (\(px)x\(px))")
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: swift \(args[0]) <source.png> <output_dir>\n", stderr)
    exit(1)
}

let sourcePath = args[1]
let outputDir = args[2]

print("Generating macOS app icons with squircle mask...")
try generateIcon(source: sourcePath, outputDir: outputDir)
print("Done!")
