import SwiftUI
import AppKit
import ServiceManagement

/// 轻量设置页：只放「开关类」和「阈值类」配置，复杂结构仍交给 rules.json。
/// 保存后重启进程生效 —— 规则在启动时读一次，热重载会让归因结果在两次扫描间跳变。
struct SettingsView: View {
    @State private var rules: Rules
    @State private var launchAtLogin: Bool
    @State private var dirty = false

    private let onClose: () -> Void
    /// 离屏渲染时 ImageRenderer 画不出 ScrollView 的内容，出图用 false
    private let scrollable: Bool

    init(onClose: @escaping () -> Void, scrollable: Bool = true) {
        _rules = State(initialValue: Rules.shared)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        self.onClose = onClose
        self.scrollable = scrollable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)
            Group {
                if scrollable {
                    ScrollView { sections }
                } else {
                    sections
                }
            }
            .frame(maxHeight: scrollable ? 520 : nil)
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 440)
        .frame(height: scrollable ? 620 : nil)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.t("设置", "Settings"))
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text("HotPot " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            general
            alertSection
            agentsSection
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 通用

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(L10n.t("通用", "General"))
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("开机自启", "Launch at login"))
                        .font(.system(size: 12.5))
                    Text(L10n.t("登录后自动驻留菜单栏", "Stay in the menu bar after login"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: launchAtLogin) { newValue in
                applyLaunchAtLogin(newValue)
            }
        }
    }

    // MARK: 预警阈值

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L10n.t("异常预警", "Alerts"))
            Text(L10n.t("某个 agent 持续超过阈值时，面板顶部会标红并显示已持续多久。",
                        "When an agent stays above the threshold, the panel flags it and shows how long."))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sliderRow(title: L10n.t("CPU 阈值", "CPU threshold"),
                      value: Binding(
                        get: { rules.alert.cpuPercent },
                        set: { rules.alert.cpuPercent = $0; dirty = true }
                      ),
                      range: 100...800, step: 50,
                      display: "\(Int(rules.alert.cpuPercent))%")

            sliderRow(title: L10n.t("持续时长", "Sustained for"),
                      value: Binding(
                        get: { rules.alert.sustainSeconds / 60 },
                        set: { rules.alert.sustainSeconds = ($0).rounded() * 60; dirty = true }
                      ),
                      range: 1...15, step: 1,
                      display: L10n.t("\(Int(rules.alert.sustainSeconds / 60)) 分钟",
                                      "\(Int(rules.alert.sustainSeconds / 60)) min"))
        }
    }

    private func sliderRow(title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(display)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }

    // MARK: Agent 开关

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(L10n.t("识别的 Agent", "Detected agents"))
            Text(L10n.t("关掉的不会被统计，也不会出现在面板里。",
                        "Disabled ones are ignored and hidden from the panel."))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            ForEach($rules.agents, id: \.id) { $agent in
                HStack(spacing: 9) {
                    Image(systemName: agent.symbol ?? "circle.dashed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 15)
                    Text(agent.name).font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { agent.enabled ?? true },
                        set: { agent.enabled = $0; dirty = true }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(.vertical, 0.5)
            }
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Button(L10n.t("打开规则文件", "Open rules file")) {
                NSWorkspace.shared.open(Rules.path)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.tint)

            Button(L10n.t("恢复默认", "Reset")) {
                rules = .default
                dirty = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.tint)

            Spacer()

            if dirty {
                Text(L10n.t("重启后生效", "Restart to apply"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Button(L10n.t("保存并重启", "Save & restart")) {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: 动作

    private func save() {
        Rules.shared = rules
        rules.save()
        relaunch()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 失败就回滚开关，别让界面显示一个不成立的状态
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

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
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
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
