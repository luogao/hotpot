import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = AppModel()
    private let settings = SettingsWindowController()
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "—°"
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            btn.action = #selector(statusItemClicked)
            btn.target = self
            // 左键开面板，右键开盘菜单（开机自启 / 退出）
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false

        NotificationCenter.default.addObserver(forName: .hotPotOpenSettings, object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }

        titleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshTitle()
        }
        RunLoop.main.add(titleTimer!, forMode: .common)

        // POC 用：启动后自动展开面板，方便截图/验收
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    private var lastTitle = ""

    private func refreshTitle() {
        guard let btn = statusItem.button else { return }
        let t = model.temperature
        let text = t > 0 ? "\(Int(t.rounded()))°" : "—°"
        // 菜单栏重绘不便宜：只有读数变了才写 attributedTitle
        guard text != lastTitle else { return }
        lastTitle = text
        // 菜单栏是毛玻璃/深浅壁纸叠加，彩色文字会糊掉。文字一律用 labelColor
        // （系统自动反色），档位信息交给前面的小圆点。
        btn.image = t > 0 ? Self.dot(color: model.level.menuColor) : nil
        btn.imagePosition = .imageLeading
        btn.imageScaling = .scaleNone
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: model.temperature >= 85 ? NSColor.systemRed : NSColor.labelColor,
        ]
        btn.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        btn.toolTip = L10n.t("\(AppInfo.name) · 芯片 \(Int(t))℃ · \(model.sessions.count) 个 agent 在跑",
                            "\(AppInfo.name) · Chip \(Int(t))℃ · \(model.sessions.count) agents")
    }

    // MARK: - 点击与菜单

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRight {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        guard let btn = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t("打开面板", "Open panel"),
                     action: #selector(togglePopover), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let login = NSMenuItem(title: L10n.t("开机自启", "Launch at login"),
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = isLaunchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(withTitle: L10n.t("偏好设置…", "Settings…"),
                     action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L10n.t("编辑规则文件…", "Edit rules file…"),
                     action: #selector(openRules), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("退出 \(AppInfo.name)", "Quit \(AppInfo.name)"),
                     action: #selector(quit), keyEquivalent: "q").target = self

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: btn.bounds.height + 4),
                   in: btn)
    }

    /// 5pt 实心圆，不随菜单栏反色（颜色本身是语义）
    private static func dot(color: NSColor) -> NSImage {
        let d: CGFloat = 6
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if popover.isShown { popover.performClose(nil) }
        settings.show()
    }

    @objc private func openRules() {
        NSWorkspace.shared.open(Rules.path)
    }

    // MARK: - 开机自启（默认关，用户从右键菜单开）

    private var isLaunchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("设置开机自启失败", "Could not change login item")
            alert.informativeText = L10n.t(
                "把 \(AppInfo.name) 拖进 /Applications 再试。\n\(error.localizedDescription)",
                "Move HotPot into /Applications and try again.\n\(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func togglePopover() {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // NSPopover 先按当前 contentSize 定位，SwiftUI 在 show 之后才完成布局。
        // 内容比预估高时窗口会向上生长，直接盖住菜单栏。先把布局跑完、尺寸定死。
        if let vc = popover.contentViewController {
            vc.view.layoutSubtreeIfNeeded()
            let fit = vc.view.fittingSize
            if fit.height > 0, fit.width > 0 { popover.contentSize = fit }
        }
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) { model.panelOpen = true }
    func popoverDidClose(_ notification: Notification) { model.panelOpen = false }
}
