#!/usr/bin/env swift
// ZeroSqueeze logo generator. Draws a 1024×1024 PNG containing:
//   • Rounded-square deep cool-ink background
//   • A bold rose→violet gradient "0" ring (Zero / cuffless)
//   • A bright white ECG / QRS pulse sweeping horizontally through the ring,
//     separated from it by a dark cut where they cross
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
    static let bgTop      = NSColor(red: 0x11/255.0, green: 0x17/255.0, blue: 0x26/255.0, alpha: 1)
    static let bgBottom   = NSColor(red: 0x0A/255.0, green: 0x0E/255.0, blue: 0x18/255.0, alpha: 1)
    static let ringStart  = NSColor(red: 0xFF/255.0, green: 0x3D/255.0, blue: 0x71/255.0, alpha: 1) // rose
    static let ringEnd    = NSColor(red: 0xA2/255.0, green: 0x4B/255.0, blue: 0xFF/255.0, alpha: 1) // violet
    static let waveform   = NSColor.white
    static let glow       = NSColor(red: 0xFF/255.0, green: 0x3D/255.0, blue: 0x71/255.0, alpha: 0.55)
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
        NSColor(red: 0xFF/255.0, green: 0x3D/255.0, blue: 0x71/255.0, alpha: 0.26),
        NSColor(red: 0xFF/255.0, green: 0x3D/255.0, blue: 0x71/255.0, alpha: 0.0)
    ])
    bloom?.draw(fromCenter: NSPoint(x: cx, y: cy), radius: 0,
                toCenter: NSPoint(x: cx, y: cy), radius: s * 0.52, options: [])

    // ── Mark: a bold "0" ring (Zero / cuffless) with a white ECG pulse cut
    //    through its middle. No letterform — a cardiac monogram. ──────────
    guard let pGrad = NSGradient(colors: [Palette.ringStart, Palette.ringEnd]) else { return nil }

    let R = s * 0.275                 // ring radius
    let lw = s * 0.125                // ring thickness
    let ringRect = NSRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R)

    // Gradient-filled ring: clip to the stroked-circle outline, draw gradient.
    NSGraphicsContext.current?.saveGraphicsState()
    let ringGlow = NSShadow()
    ringGlow.shadowColor = Palette.glow
    ringGlow.shadowBlurRadius = s * 0.05
    ringGlow.shadowOffset = .zero
    ringGlow.set()
    let circle = CGPath(ellipseIn: ringRect, transform: nil)
    let ringStroke = circle.copy(strokingWithWidth: lw, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.cgContext.saveGState()
    ctx.cgContext.addPath(ringStroke)
    ctx.cgContext.clip()
    pGrad.draw(in: ringRect.insetBy(dx: -lw, dy: -lw), angle: -45)
    ctx.cgContext.restoreGState()
    NSGraphicsContext.current?.restoreGraphicsState()

    // ECG pulse sweeping horizontally through the ring centre. A dark "cut"
    // stroke underneath separates the white line from the ring where they
    // cross; the white QRS spike sits on top with a soft glow.
    let mid = cy
    func ecgPath(width strokeW: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx - s * 0.40, y: mid))
        p.addLine(to: CGPoint(x: cx - s * 0.13, y: mid))
        p.addLine(to: CGPoint(x: cx - s * 0.075, y: mid + s * 0.055))   // small P
        p.addLine(to: CGPoint(x: cx - s * 0.020, y: mid - s * 0.060))   // Q dip
        p.addLine(to: CGPoint(x: cx + s * 0.030, y: mid + s * 0.185))   // tall R
        p.addLine(to: CGPoint(x: cx + s * 0.075, y: mid - s * 0.085))   // S
        p.addLine(to: CGPoint(x: cx + s * 0.120, y: mid))
        p.addLine(to: CGPoint(x: cx + s * 0.40, y: mid))
        return p.copy(strokingWithWidth: strokeW, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }
    // Dark separation cut.
    ctx.cgContext.saveGState()
    ctx.cgContext.addPath(ecgPath(width: s * 0.085))
    ctx.cgContext.setFillColor(Palette.bgBottom.cgColor)
    ctx.cgContext.fillPath()
    ctx.cgContext.restoreGState()
    // White pulse line with glow.
    NSGraphicsContext.current?.saveGraphicsState()
    let lineGlow = NSShadow()
    lineGlow.shadowColor = NSColor.white.withAlphaComponent(0.5)
    lineGlow.shadowBlurRadius = s * 0.02
    lineGlow.shadowOffset = .zero
    lineGlow.set()
    ctx.cgContext.addPath(ecgPath(width: s * 0.045))
    ctx.cgContext.setFillColor(Palette.waveform.cgColor)
    ctx.cgContext.fillPath()
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
