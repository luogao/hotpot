import SwiftUI
import AppKit

/// 资源看板：过去 N 小时里谁在烧 CPU。
/// 数据来自 MetricsStore 的 SQLite 采样，图表全部手绘（和面板同一套视觉，不引 Swift Charts）。
struct DashboardView: View {

    enum Span: String, CaseIterable, Identifiable {
        case h1, h24, d7, d30
        var id: String { rawValue }

        var label: String {
            switch self {
            case .h1: return "1h"
            case .h24: return "24h"
            case .d7: return "7d"
            case .d30: return "30d"
            }
        }

        var seconds: Int {
            switch self {
            case .h1: return 3600
            case .h24: return 86_400
            case .d7: return 7 * 86_400
            case .d30: return 30 * 86_400
            }
        }

        /// 温度折线聚合粒度：一小时内按分钟，越长的窗口桶越大
        var bucket: Int {
            switch self {
            case .h1: return 60
            case .h24: return 300
            case .d7: return 3600
            case .d30: return 6 * 3600
            }
        }
    }

    var onClose: () -> Void = {}

    @State private var span: Span = .h24
    @State private var agents: [MetricsStore.AgentTotal] = []
    @State private var temps: [MetricsStore.TempPoint] = []
    @State private var ports: [MetricsStore.PortTotal] = []
    @State private var summary = MetricsStore.Summary()
    @State private var loaded = false

    /// preload=true 走同步查询：离屏快照没有窗口，onAppear 不会触发
    init(onClose: @escaping () -> Void = {}, preload: Bool = false) {
        self.onClose = onClose
        guard preload else { return }
        let span = Span.h24
        let since = Int(Date().timeIntervalSince1970) - span.seconds
        let store = MetricsStore.shared
        _agents = State(initialValue: store.agentTotals(since: since))
        _temps = State(initialValue: store.temps(since: since, bucket: span.bucket))
        _ports = State(initialValue: store.portTotals(since: since))
        _summary = State(initialValue: store.summary(since: since))
        _loaded = State(initialValue: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollFade(space: "dashboardScroll", tint: Theme.bg, bottomInset: 24) {
                VStack(alignment: .leading, spacing: 26) {
                    if loaded && agents.isEmpty && summary.cpuSeconds == 0 {
                        emptyState
                    } else {
                        statCards
                        cpuSection
                        tempSection
                        portSection
                    }
                }
                .padding(EdgeInsets(top: 18, leading: 28, bottom: 0, trailing: 28))
            }
            footer
        }
        .frame(width: 640, height: 760)
        .background(Theme.bg)
        .onAppear { reload() }
        .onChange(of: span) { _ in reload() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.t("资源看板", "Resource dashboard"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(Span.allCases) { s in
                    Button {
                        span = s
                    } label: {
                        Text(s.label)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(span == s ? Theme.bg : Theme.ink2)
                            .frame(width: 40, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(span == s ? Theme.accent : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.ink2.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 20, leading: 28, bottom: 10, trailing: 22))
    }

    // MARK: - 数字卡

    private var statCards: some View {
        HStack(spacing: 12) {
            let cpu = splitDuration(summary.cpuSeconds)
            statCard(cpu.0, cpu.1, L10n.t("CPU 总时长", "total CPU"))
            statCard(summary.peakTemp > 0 ? "\(Int(summary.peakTemp))" : "—",
                     summary.peakTemp > 0 ? "℃" : "", L10n.t("峰值温度", "peak temp"))
            statCard("\(summary.agents)", L10n.t("个", "agents"), L10n.t("活跃 agent", "active agents"))
        }
    }

    private func statCard(_ value: String, _ unit: String = "", _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink2.opacity(0.75))
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.ink2.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: - CPU 分布

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHead(L10n.t("CPU 时间分布", "CPU time"))
            if agents.isEmpty {
                Text(L10n.t("这段时间没有 agent 消耗 CPU", "No agent CPU in this window"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink2.opacity(0.55))
                    .padding(.vertical, 8)
            } else {
                let top = Array(agents.prefix(6))
                let maxCPU = max(top.first?.cpuSeconds ?? 1, 0.001)
                VStack(spacing: 9) {
                    ForEach(Array(top.enumerated()), id: \.element.agent) { _, a in
                        HStack(spacing: 12) {
                            AgentIcon(id: a.agent, symbol: symbolFor(a.agent), size: 15)
                                .frame(width: 16)
                            Text(displayName(a.agent))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 92, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent.opacity(0.85))
                                    .frame(width: max(2, g.size.width * a.cpuSeconds / maxCPU))
                            }
                            .frame(height: 9)
                            Text(duration(a.cpuSeconds))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.ink2)
                                .frame(width: 62, alignment: .trailing)
                        }
                        .frame(height: 18)
                    }
                }
            }
        }
    }

    // MARK: - 温度

    private var tempSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHead(L10n.t("温度", "Temperature"))
                Spacer()
                if let peak = temps.max(by: { $0.celsius < $1.celsius }) {
                    Text("\(Int(peak.celsius))℃ " + L10n.t("峰值", "peak"))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.ink2.opacity(0.6))
                }
            }
            if temps.count < 2 {
                Text(L10n.t("温度采样点还不够", "Not enough temperature samples yet"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink2.opacity(0.55))
                    .padding(.vertical, 20)
            } else {
                TempChart(points: temps, span: span)
                    .frame(height: 116)
            }
        }
    }

    // MARK: - 端口

    private var portSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHead(L10n.t("端口占用", "Ports"))
            if ports.isEmpty {
                Text(L10n.t("这段时间没有开发服务在占端口", "No dev servers on ports"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink2.opacity(0.55))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ports.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 12) {
                            Text(verbatim: ":\(p.port)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.ink3)
                                .frame(width: 64, alignment: .leading)
                            Text(p.command)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.ink2)
                            Spacer(minLength: 0)
                            Text(approxDuration(p.samples))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.ink2.opacity(0.7))
                        }
                        .frame(height: 28)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 页脚 / 空态

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L10n.t("本地采样 · 不上传", "local only · nothing leaves this Mac"))
                .font(.system(size: 9))
                .foregroundStyle(Theme.ink2.opacity(0.45))
            Spacer(minLength: 0)
            Button(L10n.t("清除历史", "Clear history")) {
                MetricsStore.shared.clearAll()
                reload()
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.ink2.opacity(0.6))
        }
        .padding(EdgeInsets(top: 10, leading: 28, bottom: 14, trailing: 28))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("还没有数据", "No data yet"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(L10n.t("让它跑一会儿：面板开着时每 5 秒采一次，关着每 30 秒一次。\n几分钟后这里就会出现谁在烧 CPU。",
                        "Give it a few minutes: samples every 5s with the panel open, 30s when closed."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }

    private func sectionHead(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Theme.ink2.opacity(0.6))
    }

    // MARK: - 数据

    private func reload() {
        let since = Int(Date().timeIntervalSince1970) - span.seconds
        let bucket = span.bucket
        DispatchQueue.global(qos: .userInitiated).async {
            let store = MetricsStore.shared
            let a = store.agentTotals(since: since)
            let t = store.temps(since: since, bucket: bucket)
            let p = store.portTotals(since: since)
            let s = store.summary(since: since)
            DispatchQueue.main.async {
                agents = a; temps = t; ports = p; summary = s
                loaded = true
            }
        }
    }

    // MARK: - 格式化

    private func duration(_ seconds: Double) -> String {
        let p = splitDuration(seconds)
        return p.1.isEmpty ? p.0 : "\(p.0) \(p.1)"
    }

    private func splitDuration(_ seconds: Double) -> (String, String) {
        if seconds < 60 { return (String(format: "%.0f", seconds), L10n.t("秒", "s")) }
        if seconds < 3600 { return (String(format: "%.0f", seconds / 60), L10n.t("分钟", "min")) }
        return (String(format: "%.1f", seconds / 3600), L10n.t("小时", "h"))
    }

    /// 端口按 60 秒一次扫描，样本数近似分钟数
    private func approxDuration(_ samples: Int) -> String {
        samples < 60 ? "\(samples) 分钟" : String(format: "%.1f 小时", Double(samples) / 60)
    }

    private func symbolFor(_ id: String) -> String {
        Rules.shared.agents.first { $0.id == id }?.symbol ?? "circle.dashed"
    }

    private func displayName(_ id: String) -> String {
        Rules.shared.agents.first { $0.id == id }?.name ?? id
    }
}

/// 温度折线：手绘，渐变填充 + 细线，横向按窗口期铺满
private struct TempChart: View {
    let points: [MetricsStore.TempPoint]
    let span: DashboardView.Span

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let now = Double(Date().timeIntervalSince1970)
            let start = now - Double(span.seconds)
            let values = points.map(\.celsius)
            let lo = max(30.0, (values.min() ?? 40) - 6)
            let hi = (values.max() ?? 80) + 4

            func x(_ ts: Int) -> CGFloat {
                let r = (Double(ts) - start) / Double(span.seconds)
                return CGFloat(max(0, min(1, r))) * w
            }
            func y(_ c: Double) -> CGFloat {
                let r = (c - lo) / max(hi - lo, 0.1)
                return h - CGFloat(max(0, min(1, r))) * (h - 8)
            }

            // 55 / 70 / 85 三条档位参考线
            for t in [55.0, 70.0, 85.0] where t > lo && t < hi {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y(t)))
                grid.addLine(to: CGPoint(x: w, y: y(t)))
                ctx.stroke(grid, with: .color(.white.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }

            var line = Path()
            var area = Path()
            area.move(to: CGPoint(x: 0, y: h))
            for (i, pt) in points.enumerated() {
                let p2 = CGPoint(x: x(pt.ts), y: y(pt.celsius))
                if i == 0 { line.move(to: p2); area.addLine(to: p2) }
                else { line.addLine(to: p2); area.addLine(to: p2) }
            }
            if let last = points.last {
                area.addLine(to: CGPoint(x: x(last.ts), y: h))
                area.closeSubpath()
            }

            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.18), Theme.accent.opacity(0.01)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .color(Theme.accent.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .overlay(alignment: .bottom) {
            HStack {
                ForEach(tickLabels, id: \.self) { t in
                    Text(t)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Theme.ink2.opacity(0.4))
                    if t != tickLabels.last { Spacer() }
                }
            }
            .offset(y: 12)
        }
        .padding(.bottom, 14)
    }

    private var tickLabels: [String] {
        switch span {
        case .h1: return ["-60m", "-40m", "-20m", "现在"]
        case .h24: return ["-24h", "-16h", "-8h", "现在"]
        case .d7: return ["-7d", "-5d", "-3d", "现在"]
        case .d30: return ["-30d", "-20d", "-10d", "现在"]
        }
    }
}


final class DashboardWindowController {
    private var window: NSWindow?

    func show() {
        // 每次打开重建，拿到最新采样（和设置页同样处理窗口复用）
        if let w = window {
            if let host = w.contentViewController as? NSHostingController<DashboardView> {
                host.rootView = DashboardView(onClose: { [weak self] in self?.window?.close() })
            }
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: DashboardView(onClose: { [weak self] in
            self?.window?.close()
        }))
        let w = NSWindow(contentViewController: hosting)
        w.title = L10n.t("\(AppInfo.name) 资源看板", "\(AppInfo.name) Dashboard")
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(red: 12/255, green: 12/255, blue: 13/255, alpha: 1)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
