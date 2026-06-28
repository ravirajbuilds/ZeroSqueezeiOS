#!/usr/bin/env swift
// ZeroSqueeze logo generator. Draws a 1024×1024 PNG containing:
//   • Rounded-square warm near-black background
//   • A thick rose→coral gradient pulse ring, open at the lower-right where
//     the waveform exits (gives the mark motion, not a closed loop)
//   • A bright white ECG / pulse waveform sweeping through the ring
// Writes to: ZeroSqueeze/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//        and: ZeroSqueeze/Resources/Assets.xcassets/Logo.imageset/Logo{,@2x,@3x}.png
//
// Usage: cd repo root && swift scripts/gen_logo.swift

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Outline path of a single character in the heavy system font (for filling
/// text with a gradient by clipping).
func glyphPath(_ str: String, pointSize: CGFloat) -> CGPath? {
    let font = NSFont.systemFont(ofSize: pointSize, weight: .black) as CTFont
    var chars = Array(str.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count),
          let g = glyphs.first else { return nil }
    return CTFontCreatePathForGlyph(font, g, nil)
}

/// A full, classic heart — point-down, centred at `c` within a `d`×`d` box.
/// Deeper lobes and a pronounced top cusp so it reads as a real heart.
func heartPath(center c: NSPoint, size d: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let x = c.x, y = c.y, w = d, h = d
    let tip = NSPoint(x: x, y: y - h * 0.46)
    p.move(to: tip)
    p.curve(to: NSPoint(x: x - w * 0.52, y: y + h * 0.22),     // left outer
            controlPoint1: NSPoint(x: x - w * 0.16, y: y - h * 0.20),
            controlPoint2: NSPoint(x: x - w * 0.52, y: y - h * 0.04))
    p.curve(to: NSPoint(x: x, y: y + h * 0.16),                // left lobe → cusp
            controlPoint1: NSPoint(x: x - w * 0.52, y: y + h * 0.52),
            controlPoint2: NSPoint(x: x - w * 0.13, y: y + h * 0.54))
    p.curve(to: NSPoint(x: x + w * 0.52, y: y + h * 0.22),     // right lobe
            controlPoint1: NSPoint(x: x + w * 0.13, y: y + h * 0.54),
            controlPoint2: NSPoint(x: x + w * 0.52, y: y + h * 0.52))
    p.curve(to: tip,                                           // right outer → tip
            controlPoint1: NSPoint(x: x + w * 0.52, y: y - h * 0.04),
            controlPoint2: NSPoint(x: x + w * 0.16, y: y - h * 0.20))
    p.close()
    return p
}

/// Re-encode a CGImage as an opaque PNG with NO alpha channel. The App Store
/// rejects any large app icon containing an alpha channel; NSBitmapImageRep
/// always writes RGBA, so flatten through a `noneSkipLast` CG context.
func opaquePNG(_ image: CGImage) -> Data? {
    let w = image.width, h = image.height
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let flat = ctx.makeImage() else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, flat, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

struct Palette {
    static let bgTop      = NSColor(red: 0x1A/255.0, green: 0x14/255.0, blue: 0x16/255.0, alpha: 1)
    static let bgBottom   = NSColor(red: 0x0C/255.0, green: 0x08/255.0, blue: 0x09/255.0, alpha: 1)
    static let ringStart  = NSColor(red: 0xFF/255.0, green: 0x4D/255.0, blue: 0x6D/255.0, alpha: 1) // rose
    static let ringEnd    = NSColor(red: 0xFF/255.0, green: 0x8A/255.0, blue: 0x4D/255.0, alpha: 1) // coral
    static let waveform   = NSColor.white
    static let glow       = NSColor(red: 0xFF/255.0, green: 0x4D/255.0, blue: 0x6D/255.0, alpha: 0.55)
}

/// `opaque` = App Store icon mode: flatten away alpha and fill the full square
/// (iOS applies the rounded-corner mask itself). The in-app Logo keeps alpha +
/// rounded corners.
func render(size: Int, opaque: Bool = false) -> Data? {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )
    guard let bitmap, let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    // Background. Opaque icon → full square (no transparent corners). In-app
    // logo → rounded-square with clear corners.
    if opaque {
        rect.fill()
    } else {
        let corner = s * 0.225
        NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).addClip()
    }
    let bg = NSGradient(colors: [Palette.bgTop, Palette.bgBottom])
    bg?.draw(in: rect, angle: -90)

    let cx = s * 0.5
    let cy = s * 0.5
    // Soft radial bloom behind the mark for depth.
    let bloom = NSGradient(colors: [
        NSColor(red: 0xFF/255.0, green: 0x4D/255.0, blue: 0x6D/255.0, alpha: 0.26),
        NSColor(red: 0xFF/255.0, green: 0x4D/255.0, blue: 0x6D/255.0, alpha: 0.0)
    ])
    bloom?.draw(fromCenter: NSPoint(x: cx, y: cy), radius: 0,
                toCenter: NSPoint(x: cx, y: cy), radius: s * 0.52, options: [])

    // ── Wordmark: a bold "Z" (rose→coral) followed by a real red heart.
    //    Sized smaller than the canvas for comfortable padding. ──────────
    guard let pGrad = NSGradient(colors: [Palette.ringStart, Palette.ringEnd]) else { return nil }
    // Real heart-red, with a little depth top→bottom.
    let heartGrad = NSGradient(colors: [
        NSColor(red: 0xFF/255.0, green: 0x3B/255.0, blue: 0x5C/255.0, alpha: 1),
        NSColor(red: 0xC8/255.0, green: 0x10/255.0, blue: 0x32/255.0, alpha: 1)
    ])!
    let pGradRect = NSRect(x: cx - s * 0.30, y: cy - s * 0.28, width: s * 0.40, height: s * 0.56)

    NSGraphicsContext.current?.saveGraphicsState()
    let mglow = NSShadow()
    mglow.shadowColor = Palette.glow
    mglow.shadowBlurRadius = s * 0.04
    mglow.shadowOffset = .zero
    mglow.set()

    // "Z": clip to the glyph outline, then fill with the brand gradient.
    if let p = glyphPath("Z", pointSize: s * 0.56) {
        let b = p.boundingBoxOfPath
        var t = CGAffineTransform(translationX: (cx - s * 0.135) - b.midX, y: cy - b.midY)
        if let tp = p.copy(using: &t) {
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(tp)
            ctx.cgContext.clip()
            pGrad.draw(in: pGradRect, angle: -45)
            ctx.cgContext.restoreGState()
        }
    }

    // Real red heart, just after the P.
    let heart = heartPath(center: NSPoint(x: cx + s * 0.150, y: cy), size: s * 0.30)
    ctx.cgContext.saveGState()
    ctx.cgContext.addPath(heart.cgPath)
    ctx.cgContext.clip()
    heartGrad.draw(in: heart.bounds, angle: -90)
    ctx.cgContext.restoreGState()

    NSGraphicsContext.current?.restoreGraphicsState()

    if opaque, let cg = bitmap.cgImage {
        return opaquePNG(cg)   // flatten away the alpha channel for the App Store
    }
    return bitmap.representation(using: .png, properties: [:])
}

/// Convert a stroked NSBezierPath into a fillable CGPath (outline of the
/// stroke) so it can be filled with a gradient.
func strokeToPath(_ path: NSBezierPath, in cg: CGContext) -> CGPath? {
    let cgPath = path.cgPath
    return cgPath.copy(strokingWithWidth: path.lineWidth,
                       lineCap: .round, lineJoin: .round, miterLimit: 10)
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url)
    print("wrote \(path)")
}

let base = FileManager.default.currentDirectoryPath
let iconDir = "\(base)/ZeroSqueeze/Resources/Assets.xcassets/AppIcon.appiconset"
let logoDir = "\(base)/ZeroSqueeze/Resources/Assets.xcassets/Logo.imageset"

if let icon = render(size: 1024, opaque: true) { write(icon, to: "\(iconDir)/AppIcon.png") }
if let l1 = render(size: 256) { write(l1, to: "\(logoDir)/Logo.png") }
if let l2 = render(size: 512) { write(l2, to: "\(logoDir)/Logo@2x.png") }
if let l3 = render(size: 768) { write(l3, to: "\(logoDir)/Logo@3x.png") }
print("done")
