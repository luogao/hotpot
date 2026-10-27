// 生成应用图标母版：1024×1024 PNG
// 视觉：深色圆角底 + 细网格 + 中心热源辐射环（仪器感，不是卡通火焰）
// 用法: swift scripts/make_icon.swift Resources/icon-1024.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon-1024.png"
/// 小尺寸（16/32）用简化版：不分段、不画网格，否则缩到 32px 会糊成一条糊线
let simple = CommandLine.arguments.contains("--simple")
let size: CGFloat = 1024
let center = CGPoint(x: size / 2, y: size / 2)

let bgTop = NSColor(calibratedRed: 0.086, green: 0.086, blue: 0.098, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.031, green: 0.031, blue: 0.039, alpha: 1)
let accent = NSColor(calibratedRed: 0.910, green: 0.635, blue: 0.188, alpha: 1)

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setShouldAntialias(true)

// macOS 图标留白
let inset: CGFloat = 84
let bg = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 190, cornerHeight: 190, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// 底色
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                         locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
}

// 细网格：大尺寸给仪器质感，小尺寸淡到可忽略
if !simple {
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.05).cgColor)
ctx.setLineWidth(1.5)
let step: CGFloat = 64
var gx = inset
while gx <= size - inset {
    ctx.move(to: CGPoint(x: gx, y: inset))
    ctx.addLine(to: CGPoint(x: gx, y: size - inset))
    gx += step
}
var gy = inset
while gy <= size - inset {
    ctx.move(to: CGPoint(x: inset, y: gy))
    ctx.addLine(to: CGPoint(x: size - inset, y: gy))
    gy += step
}
ctx.strokePath()
}

// 中心热源光晕
if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [accent.withAlphaComponent(0.40).cgColor,
                                  accent.withAlphaComponent(0.10).cgColor,
                                  accent.withAlphaComponent(0).cgColor] as CFArray,
                         locations: [0, 0.45, 1]) {
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 40,
                           endCenter: center, endRadius: 400, options: [])
}

// 270° 刻度环：20 段，前 13 段点亮 —— 和面板里的温度刻度是同一套语言
let track = NSColor(calibratedRed: 0.204, green: 0.204, blue: 0.224, alpha: 1)
let startAngle: CGFloat = 135 * .pi / 180
let sweep: CGFloat = 270 * .pi / 180
if simple {
    // 一条 270° 粗弧 + 大圆点，32px 下依然读得出「仪表」
    ctx.setLineWidth(64)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(accent.cgColor)
    ctx.addArc(center: center, radius: 292, startAngle: startAngle, endAngle: startAngle + sweep, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(accent.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 74, y: center.y - 74, width: 148, height: 148))
} else {
let segments = 24
let lit = 16
let gap: CGFloat = 1.9 * .pi / 180
ctx.setLineWidth(17)
ctx.setLineCap(.round)
for i in 0..<segments {
    let a0 = startAngle + sweep * CGFloat(i) / CGFloat(segments) + gap
    let a1 = startAngle + sweep * CGFloat(i + 1) / CGFloat(segments) - gap
    if i < lit {
        // 越靠末端越亮：热量沿刻度累积的暗喻，比整圈同色更像仪表
        let t = CGFloat(i) / CGFloat(max(lit - 1, 1))
        ctx.setStrokeColor(accent.withAlphaComponent(0.48 + 0.52 * t).cgColor)
    } else {
        ctx.setStrokeColor(track.cgColor)
    }
    ctx.addArc(center: center, radius: 284, startAngle: a0, endAngle: a1, clockwise: false)
    ctx.strokePath()
}

// 核心：柔光托底 + 克制的实心点，避免读成靶心
ctx.setFillColor(accent.withAlphaComponent(0.13).cgColor)
ctx.fillEllipse(in: CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184))
ctx.setFillColor(accent.cgColor)
ctx.fillEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92))
}

ctx.restoreGState()

// 内描边
ctx.addPath(bgPath)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor)
ctx.setLineWidth(3)
ctx.strokePath()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(rep.pixelsWide))px)")
