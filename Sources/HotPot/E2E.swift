import Foundation
import AppKit
import SwiftUI

/// `HotPot --e2e`：不需要窗口、不需要辅助功能权限的自检。
/// 覆盖「启动链路能不能走通、视图能不能建、存储能不能读写」，
/// 用来兜住 CI 里最容易漏的那类回归（崩在启动、视图空白、SQL 写坏）。
enum E2E {
    private static var failures = 0

    static func run() -> Int32 {
        failures = 0
        print("HotPot e2e")

        // 1) 规则表
        let rules = Rules.shared.agents
        check("规则表", rules.count >= 10, "\(rules.count) 项")

        // 2) 进程扫描
        let procs = ProcessScanner().scan()
        check("进程扫描", procs.count > 10, "\(procs.count) 个进程")

        // 3) 会话聚合不崩
        let sessions = SessionAggregator.build(from: procs)
        check("会话聚合", true, "\(sessions.count) 个会话")

        // 4) 存储读写
        let dbPath = NSTemporaryDirectory() + "hotpot-e2e-\(UUID().uuidString).sqlite"
        let store = MetricsStore(path: dbPath)
        let now = Int(Date().timeIntervalSince1970)
        store.record(agents: [(id: "e2e", cpuPercent: 100, memMB: 1, procs: 1)],
                     temp: 66, ports: [], at: now, interval: 1)
        store.flush()
        let totals = store.agentTotals(since: now - 60)
        check("存储写入/查询", totals.count == 1 && abs(totals[0].cpuSeconds - 1) < 0.01,
              String(format: "%.2fs", totals.first?.cpuSeconds ?? -1))
        try? FileManager.default.removeItem(atPath: dbPath)

        // 5) 三个视图能建出来并且有内容
        MainActor.assumeIsolated {
            let model = AppModel()
            check("面板视图", renders(PanelView(model: model, scrollable: true), in: CGSize(width: 340, height: 580)),
                  "340×580")
            check("设置页视图", renders(SettingsView(onClose: {}, scrollable: true), in: CGSize(width: 640, height: 760)),
                  "640×760")
            check("看板视图", renders(DashboardView(), in: CGSize(width: 640, height: 760)),
                  "640×760")
        }

        print(failures == 0 ? "e2e passed" : "e2e failed: \(failures) 项")
        return failures == 0 ? 0 : 1
    }

    /// 离屏布局一次，返回视图是否建出了实际内容
    @MainActor
    private static func renders<V: View>(_ view: V, in size: CGSize) -> Bool {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        return !host.subviews.isEmpty && host.fittingSize.height > 20
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            print("  [ok] \(name)\(detail.isEmpty ? "" : "  \(detail)")")
        } else {
            failures += 1
            print("  [fail] \(name)\(detail.isEmpty ? "" : "  \(detail)")")
        }
    }
}
