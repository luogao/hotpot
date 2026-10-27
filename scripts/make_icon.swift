// 生成 AppIcon.icns 的母版：1024×1024 PNG
// 用法: swift scripts/make_icon.swift Resources/icon-1024.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon-1024.png"
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))

func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: symbol.size)
    out.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// macOS 图标留白：内容区约 856，四角圆角 190
let inset: CGFloat = 84
let bg = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 190, cornerHeight: 190, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let colors = [
    NSColor(calibratedRed: 0.098, green: 0.098, blue: 0.107, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.039, alpha: 1).cgColor,
] as CFArray
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
}
ctx.restoreGState()

ctx.addPath(bgPath)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor)
ctx.setLineWidth(3)
ctx.strokePath()

// 温度计：琥珀色单色，居中
let accent = NSColor(calibratedRed: 0.910, green: 0.635, blue: 0.188, alpha: 1)
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular)
if let raw = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let sym = tinted(raw, accent)
    let s = sym.size
    sym.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2,
                        width: s.width, height: s.height))
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(rep.pixelsWide))px)")
