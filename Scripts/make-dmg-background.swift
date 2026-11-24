import AppKit

// Render at both Finder display densities.
// Створюємо тло для звичайної та підвищеної щільності Finder.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let width: CGFloat = 660
let height: CGFloat = 388
let middle = width / 2
let arrowCenterY = height - 208
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func line(_ text: String, at top: CGFloat, font: NSFont, ink: NSColor) {
    let value = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
    let size = value.size()
    value.draw(at: NSPoint(x: middle - size.width / 2, y: height - top - size.height))
}

for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not allocate the Finder background / Не вдалося створити тло Finder")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    NSGradient(starting: color(0.985, 0.993, 1), ending: color(0.82, 0.925, 0.95))?
        .draw(in: canvas, angle: -34)

    line("DeepL-oFM", at: 31, font: .systemFont(ofSize: 37, weight: .bold),
         ink: color(0.07, 0.15, 0.27))
    line("Drag DeepL-oFM to Applications", at: 87, font: .systemFont(ofSize: 16, weight: .medium),
         ink: color(0.19, 0.34, 0.46))

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: middle - 35, y: arrowCenterY))
    arrow.line(to: NSPoint(x: middle + 35, y: arrowCenterY))
    arrow.move(to: NSPoint(x: middle + 22, y: arrowCenterY + 13))
    arrow.line(to: NSPoint(x: middle + 35, y: arrowCenterY))
    arrow.line(to: NSPoint(x: middle + 22, y: arrowCenterY - 13))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0.10, 0.36, 0.53).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = canvas.size
    guard let data = bitmap.tiffRepresentation else {
        fatalError("Could not encode the Finder background / Не вдалося зберегти тло Finder")
    }
    try data.write(to: output.appendingPathComponent("background-\(scale)x.tiff"))
}
