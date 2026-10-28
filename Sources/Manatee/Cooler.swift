import Foundation

/// 降温 = 把进程的调度策略降到 Background QoS。
/// 效果：任务被挪到高能效核继续跑，不冻结、不杀进程；温度实测可降 20℃+。
/// 恢复 = taskpolicy -B。
enum Cooler {

    static let binary = "/usr/sbin/taskpolicy"

    @discardableResult
    static func cool(pids: [pid_t]) -> [pid_t] {
        apply(flag: "-b", pids: pids)
    }

    @discardableResult
    static func restore(pids: [pid_t]) -> [pid_t] {
        apply(flag: "-B", pids: pids)
    }

    private static func apply(flag: String, pids: [pid_t]) -> [pid_t] {
        var ok: [pid_t] = []
        for pid in pids where pid > 1 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = [flag, "-p", String(pid)]
            p.standardError = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            do {
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 { ok.append(pid) }
            } catch {
                continue
            }
        }
        return ok
    }

    /// 批量调用（一次 fork 处理多个 pid 更快：taskpolicy 不支持下多 pid，需循环）
    static func isAvailable() -> Bool { FileManager.default.isExecutableFile(atPath: binary) }
}
