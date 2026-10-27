import SwiftUI

// 视觉规格来自 Open Design 的 A 方案「Instrument」：
// 340×540，深色 #0C0C0D，等宽大数字，20 格温度刻度，单色线条图标，唯一强调色琥珀。

enum Theme {
    static let bg     = Color(red: 12/255,  green: 12/255,  blue: 13/255)   // #0C0C0D
    static let ink    = Color(red: 242/255, green: 242/255, blue: 239/255)  // #F2F2EF
    static let ink2   = Color(red: 150/255, green: 150/255, blue: 143/255)  // #96968F
    static let ink3   = Color(red: 216/255, green: 216/255, blue: 210/255)  // #D8D8D2
    static let accent = Color(red: 232/255, green: 162/255, blue: 48/255)   // #E8A230
    static let danger = Color(red: 217/255, green: 79/255,  blue: 61/255)   // #D94F3D
    static let track  = Color(red: 38/255,  green: 38/255,  blue: 42/255)   // #26262A
    static let line   = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.07)
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingKill = false

    private var isDanger: Bool { model.temperature >= 85 }
    private var accent: Color { isDanger ? Theme.danger : Theme.accent }

    var body: some View {
        VStack(spacing: 0) {
            header
            readout
            content
            if !model.devServices.isEmpty { devServicesBar }
            footer
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
        .frame(width: 340)
        .frame(minHeight: 380)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: 顶部状态 + 主按钮

    private var header: some View {
        HStack(spacing: 8) {
            let alerting = model.alertCount > 0
            Circle()
                .fill(alerting ? Theme.danger : accent)
                .frame(width: 5, height: 5)
            Text(alerting ? L10n.t("\(model.alertCount) 个持续满载", "\(model.alertCount) sustained") : model.level.label)
                .font(.system(size: 11))
                .tracking(0.6)
                .foregroundStyle((alerting || isDanger) ? Theme.danger : Theme.ink2)
            Spacer(minLength: 8)
            if model.cooled.isEmpty {
                OutlineButton(title: L10n.t("全部降温", "Cool all"), tint: accent) { model.coolAll() }
            } else {
                OutlineButton(title: L10n.t("恢复全速", "Restore"), tint: accent) { model.restoreAll() }
            }
        }
        .frame(height: 30)
    }

    // MARK: 温度读数

    private var readout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // baseline 对齐：数字和 °C 坐同一条基线，比 top 对齐靠 padding 凑更准
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.temperature > 0 ? "\(Int(model.temperature.rounded()))" : "—")
                    .font(.system(size: 72, weight: .medium, design: .monospaced))
                    .tracking(-3.6)
                    .foregroundStyle(isDanger ? Theme.danger : Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                Text("°C")
                    .font(.system(size: 19, design: .monospaced))
                    .foregroundStyle(isDanger ? Theme.danger.opacity(0.7) : Theme.ink2)
            }
            // monospaced 数字行高约 1.2 倍字号，上下各留 ~12pt 空白，这里收掉下行空白
            .padding(.bottom, -4)

            Text(L10n.t("最热传感器", "hottest sensor") + " · " + (model.sensorName.isEmpty ? "—" : model.sensorName))
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .padding(.top, 5)

            ScaleBar(celsius: model.temperature, color: accent)
                .padding(.top, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    // MARK: 会话列表

    @ViewBuilder
    private var content: some View {
        if model.sessions.isEmpty {
            emptyState
        } else {
            let shown = Array(model.sessions.prefix(4))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.rootPid) { i, s in
                    SessionRow(session: s,
                               cooled: model.isCooled(s),
                               alert: model.alerts[s.rootPid],
                               accent: accent,
                               action: { model.toggleCool(s) })
                    if i < shown.count - 1 {
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("当前没有 agent 在跑", "No agents running"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(L10n.t("Claude Code / Codex / Cursor 一启动就会出现在这里", "They show up here as soon as you start one"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 2)
    }

    // MARK: 残留开发服务

    private var devServicesBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                Text(L10n.t("\(model.devServices.count) 个服务仍在占端口", "\(model.devServices.count) services holding ports"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                Spacer(minLength: 0)
                Button(L10n.t("关闭", "Kill")) { confirmingKill = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(model.devServices.prefix(4).map { ":\($0.port) \($0.command)" }.joined(separator: "   "))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, 14)
        .alert(L10n.t("关闭 \(model.devServices.count) 个开发服务？", "Kill \(model.devServices.count) dev services?"), isPresented: $confirmingKill) {
            Button(L10n.t("关闭进程", "Kill processes"), role: .destructive) { model.killDevServices() }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(model.devServices.map { ":\($0.port) \($0.command)" }.joined(separator: "、"))
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L10n.t("\(model.processCount) 个进程 · \(model.cooled.count) 个已降温", "\(model.processCount) processes · \(model.cooled.count) cooled"))
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(Theme.ink2)
            Spacer(minLength: 0)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ink2.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help(L10n.t("退出 HotPot", "Quit HotPot"))
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

// MARK: - 刻度

/// 20 格温度刻度：30–100°C 线性映射（与设计稿一致）
struct ScaleBar: View {
    let celsius: Double
    let color: Color
    private let count = 20

    private var lit: Int {
        guard celsius > 0 else { return 0 }
        let ratio = (celsius - 30) / 70
        return max(0, min(count, Int((ratio * Double(count)).rounded())))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? color : Theme.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - 会话行

struct SessionRow: View {
    let session: AgentSession
    let cooled: Bool
    /// 连续满载已持续的秒数（未达阈值时 nil）
    let alert: TimeInterval?
    let accent: Color
    let action: () -> Void

    private var alerting: Bool { alert != nil && !cooled }

    private var subtitle: String {
        if session.hasOtherUid { return L10n.t("root 进程 · 无法降温", "root process · cannot cool") }
        if cooled { return L10n.t("已降到能效核 · 任务继续跑", "On efficiency cores · still running") }
        if let alert { return L10n.t("连续满载 \(Self.duration(alert))", "Sustained \(Self.duration(alert))") }
        let n = session.pids.count
        return L10n.t("\(session.summary) · \(n) 进程",
                      "\(session.summary) · \(n) " + (n == 1 ? "proc" : "procs"))
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return L10n.isChinese ? (m > 0 ? "\(m) 分 \(sec) 秒" : "\(sec) 秒") : (m > 0 ? "\(m)m \(sec)s" : "\(sec)s")
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: session.def.symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.ink2)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.def.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(alerting ? Theme.danger.opacity(0.9) : Theme.ink2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(String(format: "%.0f%%", session.cpuPercent))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(alerting ? Theme.danger : Theme.ink3)
                .frame(width: 48, alignment: .trailing)

            Button(action: action) {
                Image(systemName: "snowflake")
                    .font(.system(size: 11.5))
                    .foregroundStyle(cooled ? accent : Theme.ink2.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(cooled ? accent.opacity(0.10) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(session.hasOtherUid)
            .help(session.hasOtherUid ? L10n.t("root 进程无法降温", "root process cannot be cooled") : (cooled ? L10n.t("恢复全速", "Restore full speed") : L10n.t("降到能效核，不中断任务", "Move to efficiency cores, keep running")))
        }
        .frame(height: 56)
        // 预警用左侧竖条标记，不用整块底色：底块会读成「卡片」，和面板的无卡片语言冲突
        .overlay(alignment: .leading) {
            if alerting {
                Rectangle()
                    .fill(Theme.danger)
                    .frame(width: 2)
                    .offset(x: -9)
            }
        }
        .opacity(session.hasOtherUid ? 0.55 : 1)
    }
}

// MARK: - 描边按钮

struct OutlineButton: View {
    let title: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(hover ? Theme.bg : tint)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(hover ? tint : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
