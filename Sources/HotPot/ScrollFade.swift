import SwiftUI

/// 统一滚动容器：隐藏系统滚动条，底部一层半透明 veil 提示「下面还有」，
/// 滚到底自动消失。面板和设置页共用，保证两处手感一致。
struct ScrollFade<Content: View>: View {
    /// 每个实例的坐标空间名必须不同，否则两个 ScrollView 会互相串味
    let space: String
    var tint: Color = Theme.bg
    var bottomInset: CGFloat = 26
    @ViewBuilder var content: Content

    @State private var hasMore = false

    var body: some View {
        GeometryReader { outer in
            ScrollView(.vertical) {
                content
                    .padding(.bottom, bottomInset)
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(
                                key: ScrollFadeKey.self,
                                value: inner.frame(in: .named(space)).maxY
                            )
                        }
                    )
            }
            .coordinateSpace(name: space)
            .scrollIndicators(.hidden)
            .onPreferenceChange(ScrollFadeKey.self) { maxY in
                // 不要包 withAnimation：首帧就得出结果，否则离屏快照拍到的是动画起点（遮罩不可见）
                let more = maxY - outer.size.height > 6
                if more != hasMore { hasMore = more }
            }
            .overlay(alignment: .bottom) {
                if hasMore {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [tint.opacity(0), tint.opacity(0.88)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 22)
                        Rectangle()
                            .fill(tint.opacity(0.88))
                            .frame(height: 14)
                    }
                    .frame(height: 36)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ScrollFadeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
