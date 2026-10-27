import SwiftUI
import AppKit
import ServiceManagement

/// C 方案「三栏参数台」：左栏导航 + 右侧参数区，深色，和主面板同源。
/// 尺寸取自设计稿：窗口 580 × 684（内容区），左栏 132，主区 padding 18/20/16，section 间距 20。
/// 控件全部自绘（PillToggle / StepButton）—— 系统 Toggle/Slider 在离屏渲染里画不出来，
/// 而且胶囊开关和刻度条才是这个产品该有的语言。
struct SettingsView: View {
    @State private var rules: Rules
    @State private var launchAtLogin: Bool
    @State private var dirty = false

    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        _rules = State(initialValue: Rules.shared)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            main
        }
        .frame(width: 580, height: 684)
        .background(Theme.bg)
    }

    // MARK: - 左栏

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOTPOT")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Theme.ink3.opacity(0.75))
            Text(L10n.t("设置", "Settings"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 3)

            VStack(spacing: 0) {
                RailItem(n: "01", label: L10n.t("通用", "General"), count: "1")
                RailItem(n: "02", label: L10n.t("预警", "Alerts"), count: "2")
                RailItem(n: "03", label: "Agent", count: "\(rules.agents.count)", isLast: true)
            }
            .padding(.top, 18)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                RailLink(title: L10n.t("打开规则文件", "Open rules file")) {
                    NSWorkspace.shared.open(Rules.path)
                }
                RailLink(title: L10n.t("恢复默认", "Reset defaults")) {
                    rules = .default
                    dirty = true
                }
                Button {
                    save()
                } label: {
                    Text(dirty ? L10n.t("保存并重启", "Save & restart") : L10n.t("保存", "Save"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 21/255, green: 14/255, blue: 4/255))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
        .frame(width: 132, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1)
        }
    }

    // MARK: - 右侧

    private var main: some View {
        VStack(alignment: .leading, spacing: 20) {
            generalSection
            alertSection
            agentsSection
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(n: "01", title: L10n.t("通用", "General"))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("开机自启", "Launch at login"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                    Text(L10n.t("登录后自动驻留菜单栏", "Stay in the menu bar after login"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                PillToggle(on: Binding(
                    get: { launchAtLogin },
                    set: { applyLaunchAtLogin($0) }
                ))
            }
            .frame(height: 50)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
    }

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(n: "02", title: L10n.t("异常预警", "Alerts"))
            Text(L10n.t("agent 持续超过阈值时，顶部标红并显示已持续多久。",
                        "When an agent stays above the threshold, the panel flags it."))
                .font(.system(size: 10))
                .foregroundStyle(Theme.ink2)
                .frame(height: 20, alignment: .top)
                .padding(.top, 4)

            StepperRow(label: L10n.t("CPU 阈值", "CPU threshold"),
                       value: "\(Int(rules.alert.cpuPercent))",
                       unit: "%",
                       dec: { rules.alert.cpuPercent = max(100, rules.alert.cpuPercent - 50); dirty = true },
                       inc: { rules.alert.cpuPercent = min(800, rules.alert.cpuPercent + 50); dirty = true })

            StepperRow(label: L10n.t("持续时长", "Sustained for"),
                       value: "\(Int(rules.alert.sustainSeconds / 60))",
                       unit: L10n.t("分钟", "min"),
                       dec: { rules.alert.sustainSeconds = max(60, rules.alert.sustainSeconds - 60); dirty = true },
                       inc: { rules.alert.sustainSeconds = min(900, rules.alert.sustainSeconds + 60); dirty = true })
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(n: "03", title: L10n.t("识别的 Agent", "Detected agents"),
                        trailing: "\(rules.agents.count)")
            ForEach(Array($rules.agents.enumerated()), id: \.offset) { idx, $agent in
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: agent.symbol ?? "circle.dashed")
                            .font(.system(size: 11))
                            .foregroundStyle((agent.enabled ?? true) ? Theme.ink3 : Theme.ink2)
                            .frame(width: 14)
                        Text(agent.name)
                            .font(.system(size: 11))
                            .foregroundStyle((agent.enabled ?? true) ? Theme.ink : Theme.ink2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text((agent.enabled ?? true) ? "ON" : "OFF")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle((agent.enabled ?? true) ? Theme.ink3 : Theme.ink2)
                        .frame(width: 44, alignment: .trailing)
                    PillToggle(on: Binding(
                        get: { agent.enabled ?? true },
                        set: { agent.enabled = $0; dirty = true }
                    ))
                }
                .frame(height: 30)
                .overlay(alignment: .top) {
                    if idx > 0 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func save() {
        guard dirty else { onClose(); return }
        Rules.shared = rules
        rules.save()
        relaunch()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            // 失败就回滚开关，别显示一个不成立的状态
            launchAtLogin = SMAppService.mainApp.status == .enabled
            let alert = NSAlert()
            alert.messageText = L10n.t("设置开机自启失败", "Could not change login item")
            alert.informativeText = L10n.t(
                "把 HotPot 拖进 /Applications 再试。\n\(error.localizedDescription)",
                "Move HotPot into /Applications and try again.\n\(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// MARK: - 组件

private struct RailItem: View {
    let n: String
    let label: String
    let count: String
    var isLast: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(n)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 0)
            Text(count)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.ink2)
        }
        .frame(height: 38)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            if isLast {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }
        }
    }
}

private struct RailLink: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(hover ? Theme.ink : Theme.ink2)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct SectionHead: View {
    let n: String
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(n)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 10))
                .tracking(0.8)
                .foregroundStyle(Theme.ink2)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .frame(height: 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
        }
    }
}

private struct StepperRow: View {
    let label: String
    let value: String
    let unit: String
    let dec: () -> Void
    let inc: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.ink2)
            }
            .frame(width: 72, alignment: .trailing)

            HStack(spacing: 4) {
                StepButton(symbol: "minus", action: dec)
                StepButton(symbol: "plus", action: inc)
            }
            .frame(width: 56, alignment: .trailing)
        }
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hover ? Theme.ink : Theme.ink2)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(hover ? Theme.accent : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 34×18 胶囊开关：ON 时琥珀描边 + 淡填充 + 圆钮右移
struct PillToggle: View {
    @Binding var on: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { on.toggle() }
        } label: {
            Capsule()
                .fill(on ? Theme.accent.opacity(0.16) : Color.clear)
                .overlay(
                    Capsule().stroke(on ? Theme.accent.opacity(0.55) : Color.white.opacity(0.18),
                                     lineWidth: 1)
                )
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(on ? Theme.accent : Color.white.opacity(0.35))
                        .frame(width: 12, height: 12)
                        .padding(2)
                }
                .frame(width: 34, height: 18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 窗口

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(onClose: { [weak self] in
            self?.window?.close()
        }))
        let w = NSWindow(contentViewController: hosting)
        w.title = L10n.t("HotPot 设置", "HotPot Settings")
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
