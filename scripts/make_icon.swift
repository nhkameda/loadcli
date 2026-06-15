#!/usr/bin/env swift
// Generates the loadcli AppIcon set procedurally (no external assets).
// Usage: swift scripts/make_icon.swift [outputDir]
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/loadcli/Resources/Assets.xcassets/AppIcon.appiconset"

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func renderIcon(px: Int) -> CGImage {
    let S = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // --- icon body (macOS squircle proportions) ---
    let inset = S * 0.0977
    let body = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let bw = body.width
    let radius = bw * 0.2237
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.010), blur: S * 0.028,
                  color: color(0, 0, 0, 0.30))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0, 0, 0, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // gradient fill (violet -> deep indigo, diagonal)
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let top = color(0.545, 0.361, 0.965)      // #8B5CF6
    let bottom = color(0.337, 0.231, 0.831)   // #563BD4
    let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // top-left sheen
    let center = CGPoint(x: body.minX + bw * 0.30, y: body.maxY - bw * 0.16)
    let sheen = CGGradient(colorsSpace: cs,
                           colors: [color(1, 1, 1, 0.22), color(1, 1, 1, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: bw * 0.72, options: [])
    ctx.restoreGState()

    // --- subtle split-pane motif (two windows side by side) ---
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let paneInset = bw * 0.165
    let paneRect = body.insetBy(dx: paneInset, dy: paneInset * 1.18)
    let panePath = CGPath(roundedRect: paneRect, cornerWidth: bw * 0.05,
                          cornerHeight: bw * 0.05, transform: nil)
    ctx.setStrokeColor(color(1, 1, 1, 0.16))
    ctx.setLineWidth(bw * 0.018)
    ctx.addPath(panePath); ctx.strokePath()
    // vertical divider
    ctx.move(to: CGPoint(x: paneRect.midX, y: paneRect.minY))
    ctx.addLine(to: CGPoint(x: paneRect.midX, y: paneRect.maxY))
    ctx.strokePath()
    ctx.restoreGState()

    // --- ">_" prompt glyph (bold, geometric, scales to 16px) ---
    ctx.saveGState()
    let lw = bw * 0.105
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(1, 1, 1, 1))
    ctx.setLineWidth(lw)
    // chevron ">"
    let cy = body.midY + bw * 0.01
    let cx = body.midX - bw * 0.135
    let cw = bw * 0.20
    let ch = bw * 0.27
    ctx.move(to: CGPoint(x: cx - cw / 2, y: cy + ch / 2))
    ctx.addLine(to: CGPoint(x: cx + cw / 2, y: cy))
    ctx.addLine(to: CGPoint(x: cx - cw / 2, y: cy - ch / 2))
    ctx.strokePath()
    // underscore "_" (cursor)
    let usY = cy - ch / 2
    let usX0 = body.midX + bw * 0.045
    let usX1 = body.midX + bw * 0.27
    let usRect = CGRect(x: usX0, y: usY - lw / 2, width: usX1 - usX0, height: lw)
    let usPath = CGPath(roundedRect: usRect, cornerWidth: lw / 2, cornerHeight: lw / 2, transform: nil)
    ctx.setFillColor(color(1, 1, 1, 1))
    ctx.addPath(usPath); ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in sizes {
    writePNG(renderIcon(px: px), to: "\(outDir)/\(name)")
    print("wrote \(name) (\(px)px)")
}
print("done -> \(outDir)")
