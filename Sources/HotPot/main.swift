import Foundation
import AppKit
import SwiftUI

// ── POC 入口：--dump 走命令行自检，其余进 GUI ──

let argv = CommandLine.arguments

if argv.contains("--dump") {
    runDump()
    exit(0)
}

if argv.contains("--cool-test") {
    // 自检：把 CPU 最高的 agent 会话整体降温，观察 CPU/温度变化，再恢复
    let scanner = ProcessScanner()
    let temp = TemperatureReader()
    _ = scanner.scan()
    Thread.sleep(forTimeInterval: 1.0)

    func snapshot(_ tag: String) -> (Double, [AgentSession]) {
        let s = SessionAggregator.build(from: scanner.scan())
        let t = temp?.hottestSilicon()?.celsius ?? 0
        let top = s.first
        print(String(format: "  [%@] 最高温 %.1f℃ | %@ %.0f%% (%d 进程)",
                     tag, t, top?.def.name ?? "无", top?.cpuPercent ?? 0, top?.pids.count ?? 0))
        return (t, s)
    }

    print("=== 降温前 ===")
    let (_, before) = snapshot("before")
    guard let top = before.first else { print("没有检测到 agent"); exit(1) }
    print("  目标: \(top.def.name) pid=\(top.rootPid) 进程数=\(top.pids.count)")

    let ok = Cooler.cool(pids: top.pids)
    print("  已降级 \(ok.count)/\(top.pids.count) 个进程")

    print("=== 降级后 25s ===")
    Thread.sleep(forTimeInterval: 25)
    _ = snapshot("cooled")

    Cooler.restore(pids: ok)
    print("=== 已恢复全速 ===")
    Thread.sleep(forTimeInterval: 20)
    _ = snapshot("restored")
    exit(0)
}

if argv.contains("--render") {
    // 离屏渲染面板 PNG（不需要屏幕录制权限）
    let model = AppModel()
    model.loadSync()
    // 演示用状态注入：--fake=91 覆盖温度，--empty 清空列表，--cooled 把第一行标为已降温
    if let f = argv.first(where: { $0.hasPrefix("--fake=") }), let v = Double(f.dropFirst(7)) {
        model.temperature = v
        if model.sensorName.isEmpty { model.sensorName = "PMU tdie8" }
    }
    if argv.contains("--empty") { model.sessions = [] }
    if argv.contains("--alert"), let first = model.sessions.first {
        model.alerts = [first.rootPid: 312]
    }
    if argv.contains("--dev") {
        model.devServices = [
            DevService(pid: 90001, port: 3000, command: "node", uptime: 5400),
            DevService(pid: 90002, port: 5173, command: "node", uptime: 2100),
            DevService(pid: 90003, port: 8000, command: "python", uptime: 720),
        ]
    }
    if argv.contains("--cooled"), let first = model.sessions.first {
        model.cooled = Set(first.pids)
    }
    let out = (argv.first(where: { $0.hasPrefix("--out=") })?.dropFirst(6)).map(String.init)
        ?? "/Users/gaogao/Documents/Hermes/whoscooking-oss/poc-panel.png"
    MainActor.assumeIsolated {
        let view = PanelView(model: model)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("rendered -> \(out)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } else {
            print("render failed")
        }
    }
    exit(0)
}

if argv.contains("--ports") {
    let list = PortScanner.scan()
    if list.isEmpty { print("没有检测到残留的开发服务") }
    for s in list {
        print(String(format: ":%d  %@  pid=%d  运行 %.0f 分钟", s.port, s.command, s.pid, s.uptime / 60))
    }
    exit(0)
}

if argv.contains("--bench") {
    let s = ProcessScanner()
    for i in 0..<4 {
        let t0 = Date()
        let p = s.scan()
        print(String(format: "scan %d: %6.1f ms  %d procs", i, Date().timeIntervalSince(t0) * 1000, p.count))
    }
    if let t = TemperatureReader() {
        for i in 0..<6 {
            let t0 = Date()
            let r = t.readAll()
            print(String(format: "temp %d: %6.1f ms  %d sensors", i, Date().timeIntervalSince(t0) * 1000, r.count))
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

// ── 自检输出 ──

func runDump() {
    print("=== 温度 ===")
    if let t = TemperatureReader() {
        if let hot = t.hottestSilicon() {
            print(String(format: "  芯片最高: %.1f℃ (%@)", hot.celsius, hot.name))
        }
        let all = t.readAll().sorted { $0.celsius > $1.celsius }.prefix(5)
        for s in all { print(String(format: "    %-16@ %5.1f℃", s.name as NSString, s.celsius)) }
    } else {
        print("  ✗ IOHID 初始化失败")
    }

    print("\n=== 诊断: rusage ===")
    do {
        var b = [UInt8](repeating: 0, count: 512)
        let kr = b.withUnsafeMutableBytes { raw -> Int32 in
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4,
                            raw.baseAddress!.assumingMemoryBound(to: rusage_info_t?.self))
        }
        let v = b.withUnsafeBytes { $0.load(as: rusage_info_v4.self) }
        print("  self kr=\(kr) user=\(v.ri_user_time) sys=\(v.ri_system_time)")
        // 挑一个同用户的别的进程
        let probe = ProcessScanner()
        let ps = probe.scan()
        if let other = ps.first(where: { $0.uid == getuid() && $0.pid != getpid() }) {
            var b2 = [UInt8](repeating: 0, count: 512)
            let kr2 = b2.withUnsafeMutableBytes { raw -> Int32 in
                proc_pid_rusage(other.pid, RUSAGE_INFO_V4,
                                raw.baseAddress!.assumingMemoryBound(to: rusage_info_t?.self))
            }
            print("  other(\(other.comm) pid=\(other.pid)) kr=\(kr2)")
        }
    }

    print("\n=== Agent 会话 ===")
    let scanner = ProcessScanner()
    _ = scanner.scan()                    // 第一次采样只建基线
    Thread.sleep(forTimeInterval: 1.0)
    let procs = scanner.scan()
    print("  进程总数: \(procs.count)")
    let sessions = SessionAggregator.build(from: procs)
    if sessions.isEmpty { print("  (无)") }
    for s in sessions {
        print(String(format: "  %@ %-13@ %6.1f%%  %d 进程  %@",
                     s.def.id as NSString, s.def.name as NSString, s.cpuPercent,
                     s.pids.count, s.summary))
        if !s.busyChildren.isEmpty {
            let kids = s.busyChildren.prefix(4).map { String(format: "%@ %.0f%%", $0.name, $0.cpu) }
            print("       子进程: " + kids.joined(separator: " | "))
        }
    }

    print("\n=== Top CPU 进程（不限 agent）===")
    for p in procs.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(6) {
        print(String(format: "  %-24@ %6.1f%%  pid=%d", SessionAggregator.shortName(p) as NSString, p.cpuPercent, p.pid))
    }
}
