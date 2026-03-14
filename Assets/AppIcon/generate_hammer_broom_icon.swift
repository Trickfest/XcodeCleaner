import AppKit

struct Palette {
    let blueTop = NSColor(calibratedRed: 0x6B / 255.0, green: 0xC8 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
    let blueMid = NSColor(calibratedRed: 0x24 / 255.0, green: 0x82 / 255.0, blue: 0xEC / 255.0, alpha: 1.0)
    let blueDeep = NSColor(calibratedRed: 0x11 / 255.0, green: 0x39 / 255.0, blue: 0x7B / 255.0, alpha: 1.0)
    let navy = NSColor(calibratedRed: 0x0A / 255.0, green: 0x1B / 255.0, blue: 0x3D / 255.0, alpha: 1.0)
    let steelLight = NSColor(calibratedRed: 0xF3 / 255.0, green: 0xF7 / 255.0, blue: 0xFB / 255.0, alpha: 1.0)
    let steelMid = NSColor(calibratedRed: 0xBE / 255.0, green: 0xC8 / 255.0, blue: 0xD6 / 255.0, alpha: 1.0)
    let steelDark = NSColor(calibratedRed: 0x73 / 255.0, green: 0x7F / 255.0, blue: 0x8D / 255.0, alpha: 1.0)
    let steelShadow = NSColor(calibratedRed: 0x45 / 255.0, green: 0x51 / 255.0, blue: 0x60 / 255.0, alpha: 1.0)
    let woodLight = NSColor(calibratedRed: 0xE1 / 255.0, green: 0xB5 / 255.0, blue: 0x76 / 255.0, alpha: 1.0)
    let woodMid = NSColor(calibratedRed: 0xB9 / 255.0, green: 0x76 / 255.0, blue: 0x37 / 255.0, alpha: 1.0)
    let woodDark = NSColor(calibratedRed: 0x72 / 255.0, green: 0x42 / 255.0, blue: 0x1E / 255.0, alpha: 1.0)
    let broomLight = NSColor(calibratedRed: 0xF2 / 255.0, green: 0xD7 / 255.0, blue: 0x95 / 255.0, alpha: 1.0)
    let broomMid = NSColor(calibratedRed: 0xC9 / 255.0, green: 0x9F / 255.0, blue: 0x55 / 255.0, alpha: 1.0)
    let broomDark = NSColor(calibratedRed: 0x78 / 255.0, green: 0x58 / 255.0, blue: 0x25 / 255.0, alpha: 1.0)
    let dust = NSColor(calibratedRed: 0xEA / 255.0, green: 0xF7 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
}

let palette = Palette()

func gradient(_ stops: [(NSColor, CGFloat)]) -> NSGradient {
    let colors = stops.map(\.0)
    let locations = stops.map(\.1)
    return locations.withUnsafeBufferPointer { buffer in
        NSGradient(colors: colors, atLocations: buffer.baseAddress!, colorSpace: .deviceRGB)!
    }
}

func roundedRect(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func polygon(_ points: [CGPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    return path
}

func rotatedPath(_ path: NSBezierPath, around center: CGPoint, degrees: CGFloat) -> NSBezierPath {
    let copy = path.copy() as! NSBezierPath
    var transform = AffineTransform()
    transform.translate(x: center.x, y: center.y)
    transform.rotate(byDegrees: degrees)
    transform.translate(x: -center.x, y: -center.y)
    copy.transform(using: transform)
    return copy
}

func makeCanvas(size: CGFloat) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
}

func setShadow(color: NSColor, blur: CGFloat, offset: CGSize) {
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
}

func drawTile(in rect: CGRect) {
    let tile = roundedRect(in: rect, radius: rect.width * 0.22)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()

    let base = gradient([
        (palette.blueTop, 0.0),
        (palette.blueMid, 0.30),
        (palette.blueDeep, 0.72),
        (palette.navy, 1.0),
    ])
    base.draw(in: tile, angle: 315)

    let topGlow = NSGradient(starting: palette.dust.withAlphaComponent(0.25), ending: .clear)!
    topGlow.draw(in: NSBezierPath(ovalIn: rect.offsetBy(dx: -rect.width * 0.08, dy: rect.height * 0.18)), angle: 270)

    let bottomShadow = NSGradient(starting: .clear, ending: palette.navy.withAlphaComponent(0.34))!
    bottomShadow.draw(in: NSBezierPath(ovalIn: rect.offsetBy(dx: rect.width * 0.15, dy: -rect.height * 0.18)), angle: 90)

    let gloss = polygon([
        CGPoint(x: rect.minX + rect.width * 0.68, y: rect.maxY),
        CGPoint(x: rect.maxX, y: rect.maxY),
        CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.62),
    ])
    palette.dust.withAlphaComponent(0.08).setFill()
    gloss.fill()

    let minor = NSBezierPath()
    let minorStep = rect.width * 0.055
    for x in stride(from: rect.minX + minorStep, through: rect.maxX, by: minorStep) {
        minor.move(to: CGPoint(x: x, y: rect.minY))
        minor.line(to: CGPoint(x: x, y: rect.maxY))
    }
    for y in stride(from: rect.minY + minorStep, through: rect.maxY, by: minorStep) {
        minor.move(to: CGPoint(x: rect.minX, y: y))
        minor.line(to: CGPoint(x: rect.maxX, y: y))
    }
    palette.dust.withAlphaComponent(0.05).setStroke()
    minor.lineWidth = max(1.0, rect.width * 0.0018)
    minor.stroke()

    let major = NSBezierPath()
    let majorStep = rect.width * 0.11
    for x in stride(from: rect.minX + majorStep, through: rect.maxX, by: majorStep) {
        major.move(to: CGPoint(x: x, y: rect.minY))
        major.line(to: CGPoint(x: x, y: rect.maxY))
    }
    for y in stride(from: rect.minY + majorStep, through: rect.maxY, by: majorStep) {
        major.move(to: CGPoint(x: rect.minX, y: y))
        major.line(to: CGPoint(x: rect.maxX, y: y))
    }
    palette.dust.withAlphaComponent(0.10).setStroke()
    major.lineWidth = max(1.0, rect.width * 0.0022)
    major.stroke()

    NSGraphicsContext.restoreGraphicsState()

    palette.dust.withAlphaComponent(0.14).setStroke()
    tile.lineWidth = max(2, rect.width * 0.004)
    tile.stroke()
}

func drawBlueprintSheet(in rect: CGRect) {
    let sheetRect = CGRect(
        x: rect.minX + rect.width * 0.20,
        y: rect.minY + rect.height * 0.19,
        width: rect.width * 0.54,
        height: rect.height * 0.52
    )
    let center = CGPoint(x: sheetRect.midX, y: sheetRect.midY)
    let sheet = rotatedPath(roundedRect(in: sheetRect, radius: rect.width * 0.04), around: center, degrees: -11)

    NSGraphicsContext.saveGraphicsState()
    setShadow(color: palette.navy.withAlphaComponent(0.20), blur: rect.width * 0.03, offset: CGSize(width: 0, height: -rect.height * 0.015))
    gradient([
        (palette.dust.withAlphaComponent(0.18), 0.0),
        (palette.dust.withAlphaComponent(0.10), 0.5),
        (palette.blueTop.withAlphaComponent(0.05), 1.0),
    ]).draw(in: sheet, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    palette.dust.withAlphaComponent(0.22).setStroke()
    sheet.lineWidth = max(2, rect.width * 0.0035)
    sheet.stroke()

    NSGraphicsContext.saveGraphicsState()
    sheet.addClip()
    let line = NSBezierPath()
    let left = sheetRect.minX + rect.width * 0.05
    let right = sheetRect.maxX - rect.width * 0.05
    let y1 = sheetRect.minY + sheetRect.height * 0.74
    let y2 = sheetRect.minY + sheetRect.height * 0.55
    let y3 = sheetRect.minY + sheetRect.height * 0.36
    let y4 = sheetRect.minY + sheetRect.height * 0.17
    line.move(to: CGPoint(x: left, y: y1))
    line.line(to: CGPoint(x: right, y: y1))
    line.move(to: CGPoint(x: left + rect.width * 0.05, y: y2))
    line.line(to: CGPoint(x: right - rect.width * 0.08, y: y2))
    line.move(to: CGPoint(x: left + rect.width * 0.02, y: y3))
    line.line(to: CGPoint(x: right - rect.width * 0.16, y: y3))
    line.move(to: CGPoint(x: left + rect.width * 0.06, y: y4))
    line.line(to: CGPoint(x: right - rect.width * 0.10, y: y4))
    palette.blueTop.withAlphaComponent(0.18).setStroke()
    line.lineWidth = max(2, rect.width * 0.0027)
    line.stroke()

    let ring = NSBezierPath()
    ring.appendOval(in: CGRect(x: sheetRect.minX + rect.width * 0.02, y: sheetRect.maxY - rect.height * 0.12, width: rect.width * 0.09, height: rect.width * 0.09))
    ring.move(to: CGPoint(x: sheetRect.minX + rect.width * 0.065, y: sheetRect.maxY - rect.height * 0.12))
    ring.line(to: CGPoint(x: sheetRect.minX + rect.width * 0.065, y: sheetRect.maxY - rect.height * 0.03))
    ring.move(to: CGPoint(x: sheetRect.minX + rect.width * 0.02, y: sheetRect.maxY - rect.height * 0.075))
    ring.line(to: CGPoint(x: sheetRect.minX + rect.width * 0.11, y: sheetRect.maxY - rect.height * 0.075))
    palette.dust.withAlphaComponent(0.16).setStroke()
    ring.lineWidth = max(1.5, rect.width * 0.0022)
    ring.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func drawHammer(in rect: CGRect) {
    let group = CGRect(
        x: rect.minX + rect.width * 0.18,
        y: rect.minY + rect.height * 0.10,
        width: rect.width * 0.38,
        height: rect.height * 0.64
    )
    let center = CGPoint(x: group.midX, y: group.midY)

    let headBody = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.20, y: group.minY + group.height * 0.62, width: group.width * 0.38, height: group.height * 0.14),
        radius: group.width * 0.055
    )
    let face = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.13, y: group.minY + group.height * 0.60, width: group.width * 0.11, height: group.height * 0.18),
        radius: group.width * 0.045
    )
    let neck = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.35, y: group.minY + group.height * 0.47, width: group.width * 0.10, height: group.height * 0.17),
        radius: group.width * 0.028
    )
    let handle = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.37, y: group.minY + group.height * 0.15, width: group.width * 0.08, height: group.height * 0.34),
        radius: group.width * 0.030
    )
    let grip = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.35, y: group.minY + group.height * 0.05, width: group.width * 0.12, height: group.height * 0.16),
        radius: group.width * 0.038
    )

    let bodyRect = CGRect(x: group.minX + group.width * 0.20, y: group.minY + group.height * 0.62, width: group.width * 0.38, height: group.height * 0.14)
    let topClaw = polygon([
        CGPoint(x: bodyRect.maxX - group.width * 0.01, y: bodyRect.maxY - group.height * 0.01),
        CGPoint(x: bodyRect.maxX + group.width * 0.16, y: bodyRect.maxY + group.height * 0.05),
        CGPoint(x: bodyRect.maxX + group.width * 0.07, y: bodyRect.midY + group.height * 0.02),
        CGPoint(x: bodyRect.maxX - group.width * 0.01, y: bodyRect.midY + group.height * 0.01),
    ])
    let bottomClaw = polygon([
        CGPoint(x: bodyRect.maxX - group.width * 0.01, y: bodyRect.midY - group.height * 0.01),
        CGPoint(x: bodyRect.maxX + group.width * 0.07, y: bodyRect.midY - group.height * 0.02),
        CGPoint(x: bodyRect.maxX + group.width * 0.16, y: bodyRect.minY - group.height * 0.05),
        CGPoint(x: bodyRect.maxX - group.width * 0.01, y: bodyRect.minY + group.height * 0.01),
    ])

    let metalPaths = [headBody, face, neck, topClaw, bottomClaw].map { rotatedPath($0, around: center, degrees: -26) }
    let handlePaths = [handle, grip].map { rotatedPath($0, around: center, degrees: -26) }

    let shadowPath = NSBezierPath()
    for path in metalPaths + handlePaths {
        shadowPath.append(path)
    }

    NSGraphicsContext.saveGraphicsState()
    setShadow(color: palette.navy.withAlphaComponent(0.28), blur: rect.width * 0.03, offset: CGSize(width: 0, height: -rect.height * 0.018))
    palette.navy.withAlphaComponent(0.14).setFill()
    shadowPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    for path in metalPaths {
        gradient([
            (palette.steelLight, 0.0),
            (palette.steelMid, 0.45),
            (palette.steelDark, 1.0),
        ]).draw(in: path, angle: 68)
        palette.dust.withAlphaComponent(0.35).setStroke()
        path.lineWidth = max(1.5, rect.width * 0.0024)
        path.stroke()
    }

    gradient([
        (palette.woodLight, 0.0),
        (palette.woodMid, 0.50),
        (palette.woodDark, 1.0),
    ]).draw(in: handlePaths[0], angle: 90)
    gradient([
        (palette.woodLight.withAlphaComponent(0.95), 0.0),
        (palette.woodMid, 0.55),
        (palette.woodDark, 1.0),
    ]).draw(in: handlePaths[1], angle: 90)
    for path in handlePaths {
        palette.dust.withAlphaComponent(0.22).setStroke()
        path.lineWidth = max(1.2, rect.width * 0.002)
        path.stroke()
    }

    let grain1 = rotatedPath(NSBezierPath(), around: center, degrees: -26)
    grain1.move(to: CGPoint(x: group.minX + group.width * 0.40, y: group.minY + group.height * 0.40))
    grain1.line(to: CGPoint(x: group.minX + group.width * 0.40, y: group.minY + group.height * 0.20))
    grain1.move(to: CGPoint(x: group.minX + group.width * 0.43, y: group.minY + group.height * 0.37))
    grain1.line(to: CGPoint(x: group.minX + group.width * 0.43, y: group.minY + group.height * 0.18))
    grain1.transform(using: {
        var t = AffineTransform()
        t.translate(x: center.x, y: center.y)
        t.rotate(byDegrees: -26)
        t.translate(x: -center.x, y: -center.y)
        return t
    }())
    palette.woodDark.withAlphaComponent(0.22).setStroke()
    grain1.lineWidth = max(1.0, rect.width * 0.0018)
    grain1.stroke()

    let highlight = NSBezierPath()
    highlight.move(to: CGPoint(x: group.minX + group.width * 0.20, y: group.minY + group.height * 0.71))
    highlight.line(to: CGPoint(x: group.minX + group.width * 0.53, y: group.minY + group.height * 0.71))
    highlight.transform(using: {
        var t = AffineTransform()
        t.translate(x: center.x, y: center.y)
        t.rotate(byDegrees: -26)
        t.translate(x: -center.x, y: -center.y)
        return t
    }())
    palette.dust.withAlphaComponent(0.42).setStroke()
    highlight.lineWidth = max(3.0, rect.width * 0.004)
    highlight.lineCapStyle = .round
    highlight.stroke()

    let notch = NSBezierPath()
    notch.move(to: CGPoint(x: bodyRect.maxX + group.width * 0.05, y: bodyRect.midY + group.height * 0.02))
    notch.line(to: CGPoint(x: bodyRect.maxX + group.width * 0.05, y: bodyRect.midY - group.height * 0.02))
    notch.transform(using: {
        var t = AffineTransform()
        t.translate(x: center.x, y: center.y)
        t.rotate(byDegrees: -26)
        t.translate(x: -center.x, y: -center.y)
        return t
    }())
    palette.steelShadow.withAlphaComponent(0.40).setStroke()
    notch.lineWidth = max(2.0, rect.width * 0.003)
    notch.lineCapStyle = .round
    notch.stroke()
}

func broomBristlesPath(in rect: CGRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.56))
    path.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.28),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.48),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.38)
    )
    path.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.06),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.16),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.06)
    )
    path.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.28),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.06),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.14)
    )
    path.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.56),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.38),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.77, y: rect.minY + rect.height * 0.49)
    )
    path.close()
    return path
}

func drawBroom(in rect: CGRect) {
    let group = CGRect(
        x: rect.minX + rect.width * 0.34,
        y: rect.minY + rect.height * 0.18,
        width: rect.width * 0.33,
        height: rect.height * 0.55
    )
    let center = CGPoint(x: group.midX, y: group.midY)
    let handle = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.40, y: group.minY + group.height * 0.73, width: group.width * 0.18, height: group.height * 0.17),
        radius: group.width * 0.06
    )
    let collar = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.34, y: group.minY + group.height * 0.53, width: group.width * 0.30, height: group.height * 0.21),
        radius: group.width * 0.08
    )
    let band = roundedRect(
        in: CGRect(x: group.minX + group.width * 0.35, y: group.minY + group.height * 0.61, width: group.width * 0.28, height: group.height * 0.05),
        radius: group.width * 0.02
    )
    let bristles = broomBristlesPath(in: group)

    let angle: CGFloat = 18
    let rotatedHandle = rotatedPath(handle, around: center, degrees: angle)
    let rotatedCollar = rotatedPath(collar, around: center, degrees: angle)
    let rotatedBand = rotatedPath(band, around: center, degrees: angle)
    let rotatedBristles = rotatedPath(bristles, around: center, degrees: angle)

    let shadowPath = NSBezierPath()
    shadowPath.append(rotatedHandle)
    shadowPath.append(rotatedCollar)
    shadowPath.append(rotatedBristles)

    NSGraphicsContext.saveGraphicsState()
    setShadow(color: palette.navy.withAlphaComponent(0.22), blur: rect.width * 0.028, offset: CGSize(width: 0, height: -rect.height * 0.014))
    palette.navy.withAlphaComponent(0.10).setFill()
    shadowPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    gradient([
        (palette.woodLight, 0.0),
        (palette.woodMid, 0.5),
        (palette.woodDark, 1.0),
    ]).draw(in: rotatedHandle, angle: 90)
    gradient([
        (palette.woodLight.withAlphaComponent(0.98), 0.0),
        (palette.woodMid, 0.45),
        (palette.woodDark, 1.0),
    ]).draw(in: rotatedCollar, angle: 90)
    gradient([
        (palette.steelLight, 0.0),
        (palette.steelMid, 0.5),
        (palette.steelDark, 1.0),
    ]).draw(in: rotatedBand, angle: 90)
    gradient([
        (palette.broomDark, 0.0),
        (palette.broomMid, 0.42),
        (palette.broomLight, 1.0),
    ]).draw(in: rotatedBristles, angle: 90)

    for path in [rotatedHandle, rotatedCollar, rotatedBand, rotatedBristles] {
        palette.dust.withAlphaComponent(0.18).setStroke()
        path.lineWidth = max(1.2, rect.width * 0.0018)
        path.stroke()
    }

    let bristleLines = NSBezierPath()
    let basePoints: [(CGFloat, CGFloat)] = [
        (0.28, 0.53), (0.34, 0.50), (0.40, 0.47), (0.46, 0.45),
        (0.52, 0.47), (0.58, 0.50), (0.64, 0.53)
    ]
    let tipPoints: [(CGFloat, CGFloat)] = [
        (0.20, 0.21), (0.27, 0.15), (0.36, 0.10), (0.46, 0.08),
        (0.58, 0.10), (0.69, 0.15), (0.78, 0.22)
    ]
    for (base, tip) in zip(basePoints, tipPoints) {
        bristleLines.move(to: CGPoint(x: group.minX + group.width * base.0, y: group.minY + group.height * base.1))
        bristleLines.line(to: CGPoint(x: group.minX + group.width * tip.0, y: group.minY + group.height * tip.1))
    }
    bristleLines.transform(using: {
        var t = AffineTransform()
        t.translate(x: center.x, y: center.y)
        t.rotate(byDegrees: angle)
        t.translate(x: -center.x, y: -center.y)
        return t
    }())
    palette.broomDark.withAlphaComponent(0.28).setStroke()
    bristleLines.lineWidth = max(1.0, rect.width * 0.0016)
    bristleLines.stroke()
}

func drawDustSweep(in rect: CGRect) {
    let sweep = NSBezierPath()
    sweep.move(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.27))
    sweep.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.24),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.18),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY + rect.height * 0.18)
    )

    NSGraphicsContext.saveGraphicsState()
    setShadow(color: palette.dust.withAlphaComponent(0.16), blur: rect.width * 0.018, offset: .zero)
    palette.dust.withAlphaComponent(0.24).setStroke()
    sweep.lineWidth = max(5.0, rect.width * 0.006)
    sweep.lineCapStyle = .round
    sweep.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let innerSweep = NSBezierPath()
    innerSweep.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.255))
    innerSweep.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.225),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.20),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.19)
    )
    palette.blueTop.withAlphaComponent(0.22).setStroke()
    innerSweep.lineWidth = max(2.5, rect.width * 0.003)
    innerSweep.lineCapStyle = .round
    innerSweep.stroke()

    let particles: [(CGFloat, CGFloat, CGFloat)] = [
        (0.58, 0.25, 0.010), (0.63, 0.24, 0.008), (0.68, 0.23, 0.006),
        (0.53, 0.24, 0.007), (0.72, 0.23, 0.005), (0.48, 0.26, 0.004)
    ]
    for (x, y, scale) in particles {
        let size = rect.width * scale
        let particle = roundedRect(
            in: CGRect(x: rect.minX + rect.width * x - size / 2, y: rect.minY + rect.height * y - size / 2, width: size, height: size),
            radius: size * 0.3
        )
        gradient([
            (palette.dust.withAlphaComponent(0.70), 0.0),
            (palette.blueTop.withAlphaComponent(0.30), 1.0),
        ]).draw(in: particle, angle: 250)
    }
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = makeCanvas(size: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create bitmap graphics context.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    defer {
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSColor.clear.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)).fill()

    let canvas = CGRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88)
    drawTile(in: canvas)
    drawBlueprintSheet(in: canvas)
    drawBroom(in: canvas)
    drawDustSweep(in: canvas)

    return rep
}

func pngData(for size: CGFloat) -> Data {
    drawIcon(size: size).representation(using: .png, properties: [:])!
}

func ensureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

func iconsetEntries() -> [(String, CGFloat)] {
    [
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
}

func appIconContentsJSON() -> Data {
    let imageEntries: [[String: String]] = [
        ["size": "16x16", "idiom": "mac", "filename": "icon_16x16.png", "scale": "1x"],
        ["size": "16x16", "idiom": "mac", "filename": "icon_16x16@2x.png", "scale": "2x"],
        ["size": "32x32", "idiom": "mac", "filename": "icon_32x32.png", "scale": "1x"],
        ["size": "32x32", "idiom": "mac", "filename": "icon_32x32@2x.png", "scale": "2x"],
        ["size": "128x128", "idiom": "mac", "filename": "icon_128x128.png", "scale": "1x"],
        ["size": "128x128", "idiom": "mac", "filename": "icon_128x128@2x.png", "scale": "2x"],
        ["size": "256x256", "idiom": "mac", "filename": "icon_256x256.png", "scale": "1x"],
        ["size": "256x256", "idiom": "mac", "filename": "icon_256x256@2x.png", "scale": "2x"],
        ["size": "512x512", "idiom": "mac", "filename": "icon_512x512.png", "scale": "1x"],
        ["size": "512x512", "idiom": "mac", "filename": "icon_512x512@2x.png", "scale": "2x"],
    ]
    let payload: [String: Any] = [
        "images": imageEntries,
        "info": [
            "version": 1,
            "author": "xcode",
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
}

let variantName = CommandLine.arguments.dropFirst().first ?? "XcodeInspiredBroomSweep"
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetRoot = cwd.appending(path: "Assets/AppIcon", directoryHint: .isDirectory)
let exportRoot = assetRoot.appending(path: variantName, directoryHint: .isDirectory)
let appIconsetRoot = exportRoot.appending(path: "AppIcon.appiconset", directoryHint: .isDirectory)

try ensureDirectory(exportRoot)
try ensureDirectory(appIconsetRoot)

let masterPNG = exportRoot.appending(path: "XcodeCleaner-\(variantName)-1024.png")
try pngData(for: 1024).write(to: masterPNG)

for (name, size) in iconsetEntries() {
    try pngData(for: size).write(to: appIconsetRoot.appending(path: name))
}

try appIconContentsJSON().write(to: appIconsetRoot.appending(path: "Contents.json"))

print("Generated \(masterPNG.path)")
print("Generated \(appIconsetRoot.path)")
