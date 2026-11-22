import AppKit

// Renders the 1024×1024 application icon used for the .icns bundle.

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let context = NSGraphicsContext.current else { exit(1) }
context.imageInterpolation = .high

let backgroundRect = NSRect(x: 32, y: 32, width: canvas - 64, height: canvas - 64)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.16, green: 0.38, blue: 0.98, alpha: 1),
    NSColor(srgbRed: 0.04, green: 0.68, blue: 0.80, alpha: 1)
])!
gradient.draw(in: backgroundPath, angle: -55)

let highlight = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.18),
    NSColor(white: 1, alpha: 0.0)
])!
highlight.draw(in: backgroundPath, relativeCenterPosition: NSPoint(x: -0.4, y: 0.5))

NSColor(white: 1, alpha: 0.16).setStroke()
backgroundPath.lineWidth = 6
backgroundPath.stroke()

let aAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 400, weight: .bold),
    .foregroundColor: NSColor.white
]
let aString = NSAttributedString(string: "A", attributes: aAttributes)
let aSize = aString.size()
aString.draw(at: NSPoint(x: 150, y: canvas / 2 - aSize.height / 2 - 20))

let hanFont = NSFont(name: "PingFangSC-Semibold", size: 360)
    ?? NSFont.systemFont(ofSize: 360, weight: .bold)
let hanAttributes: [NSAttributedString.Key: Any] = [
    .font: hanFont,
    .foregroundColor: NSColor(white: 1, alpha: 0.96)
]
let hanString = NSAttributedString(string: "文", attributes: hanAttributes)
let hanSize = hanString.size()
hanString.draw(at: NSPoint(x: canvas - 150 - hanSize.width, y: canvas / 2 - hanSize.height / 2 - 20))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

let output = URL(fileURLWithPath: "build/icon-master.png")
try png.write(to: output)
print("Wrote \(output.path)")
