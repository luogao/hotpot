import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = AppModel()
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "—°"
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            btn.action = #selector(togglePopover)
            btn.target = self
        }

        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false

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
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: t > 0 ? model.level.color : NSColor.secondaryLabelColor,
        ]
        btn.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        btn.toolTip = "WhoCooking · 芯片 \(Int(t))℃ · \(model.sessions.count) 个 agent 在跑"
    }

    @objc private func togglePopover() {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) { model.panelOpen = true }
    func popoverDidClose(_ notification: Notification) { model.panelOpen = false }
}
