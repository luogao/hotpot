import SwiftUI
import AppKit

/// 品牌图标：lobehub/icons 的单色 SVG 预渲染成 PNG（Resources/Icons/<id>.png）。
/// 用 template mode + 线性渐变填充，保证和面板的琥珀/深灰语言一致，而不是每个 logo 各带一套配色。
enum IconStore {
    private static var cache: [String: NSImage] = [:]

    static func image(_ id: String) -> NSImage? {
        if let hit = cache[id] { return hit }
        guard let dir = Bundle.main.resourcePath else { return nil }
        let path = dir + "/Icons/\(id).png"
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        img.isTemplate = true
        cache[id] = img
        return img
    }
}

/// agent / 进程图标。没有品牌图（aider、Xcode、ffmpeg…）就退回 SF Symbol 线条图。
struct AgentIcon: View {
    let id: String
    let symbol: String
    var size: CGFloat = 14
    var dim: Bool = false

    private var gradient: LinearGradient {
        LinearGradient(colors: dim
                       ? [Theme.ink2.opacity(0.9), Theme.ink2.opacity(0.62)]
                       : [Theme.ink, Theme.ink2],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        Group {
            if let img = IconStore.image(id) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size - 1.5, weight: .regular))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(gradient)
    }
}
