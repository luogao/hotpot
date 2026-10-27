import Testing
import Foundation
@testable import HotPot

private func p(_ path: String, args: String = "", pid: pid_t, ppid: pid_t,
               pgid: pid_t? = nil, cpu: Double = 0) -> ProcInfo {
    var info = ProcInfo(pid: pid, ppid: ppid, pgid: pgid ?? pid, uid: 501,
                        comm: (path as NSString).lastPathComponent,
                        path: path, args: args)
    info.cpuPercent = cpu
    return info
}

@Suite("会话聚合")
struct SessionAggregatorTests {

    /// 父 claude + 子 node + 孙子进程归成一行，CPU 累加
    @Test("父子进程并成一个会话")
    func 父子归并() {
        let procs = [
            p("/Users/x/.claude/local/claude", args: "claude", pid: 100, ppid: 1, cpu: 40),
            p("/opt/homebrew/bin/node", args: "node /Users/x/.claude/local/claude", pid: 101, ppid: 100, cpu: 25),
            p("/usr/bin/git", args: "git status", pid: 102, ppid: 101, cpu: 5),
        ]
        let sessions = SessionAggregator.build(from: procs, rules: [claudeRule])
        #expect(sessions.count == 1)
        #expect(sessions[0].rootPid == 100)
        #expect(sessions[0].pids == [100, 101, 102])
        #expect(sessions[0].cpuPercent == 70)
    }

    /// 两个互不相干的 claude 应该是两行，按 CPU 降序
    @Test("多个根各自成行并按 CPU 排序")
    func 多根排序() {
        let procs = [
            p("/Users/x/.claude/local/claude", args: "claude", pid: 200, ppid: 1, cpu: 12),
            p("/Users/x/.claude/local/claude", args: "claude", pid: 300, ppid: 1, cpu: 88),
        ]
        let sessions = SessionAggregator.build(from: procs, rules: [claudeRule])
        #expect(sessions.count == 2)
        #expect(sessions[0].rootPid == 300)
        #expect(sessions[1].rootPid == 200)
    }

    /// 没有命中规则时返回空，不能凭空造行
    @Test("无匹配返回空")
    func 无匹配() {
        let procs = [p("/usr/bin/top", args: "top", pid: 400, ppid: 1)]
        #expect(SessionAggregator.build(from: procs, rules: [claudeRule]).isEmpty)
    }
}

private let claudeRule = AgentDef(id: "claude", name: "Claude Code", symbol: "asterisk",
                                  patterns: ["claude"], excludes: ["Claude.app"],
                                  bin: nil, detect: [])

@Suite("看板存储")
struct MetricsStoreTests {

    private func tempStore() -> (MetricsStore, String) {
        let path = NSTemporaryDirectory() + "hotpot-test-\(UUID().uuidString).sqlite"
        return (MetricsStore(path: path), path)
    }

    @Test("采样按 CPU 秒累加")
    func cpu累加() throws {
        let (store, path) = tempStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let now = Int(Date().timeIntervalSince1970)

        // 50% × 10 秒 = 5 CPU 秒，记两次
        store.record(agents: [(id: "claude", cpuPercent: 50, memMB: 100, procs: 3)],
                     temp: 60, ports: [], at: now - 20, interval: 10)
        store.record(agents: [(id: "claude", cpuPercent: 50, memMB: 100, procs: 3)],
                     temp: 62, ports: [], at: now - 10, interval: 10)
        store.flush()

        let totals = store.agentTotals(since: now - 3600)
        #expect(totals.count == 1)
        #expect(abs(totals[0].cpuSeconds - 10) < 0.001)

        let summary = store.summary(since: now - 3600)
        #expect(abs(summary.cpuSeconds - 10) < 0.001)
        #expect(summary.peakTemp == 62)
        #expect(summary.agents == 1)
    }

    @Test("窗口期筛掉范围外的采样")
    func 窗口期() throws {
        let (store, path) = tempStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let now = Int(Date().timeIntervalSince1970)

        store.record(agents: [(id: "claude", cpuPercent: 100, memMB: 0, procs: 1)],
                     temp: 70, ports: [], at: now - 7200, interval: 10)   // 2 小时前
        store.record(agents: [(id: "claude", cpuPercent: 100, memMB: 0, procs: 1)],
                     temp: 71, ports: [], at: now - 60, interval: 10)     // 1 分钟前
        store.flush()

        let hour = store.agentTotals(since: now - 3600)
        #expect(abs(hour[0].cpuSeconds - 10) < 0.001)   // 只算最近那条
        let day = store.agentTotals(since: now - 86400)
        #expect(abs(day[0].cpuSeconds - 20) < 0.001)
    }

    @Test("48 小时前的数据压进小时表，原始行删除")
    func rollup() throws {
        let (store, path) = tempStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let now = Int(Date().timeIntervalSince1970)
        let old = now - 72 * 3600

        store.record(agents: [(id: "codex", cpuPercent: 100, memMB: 0, procs: 2)],
                     temp: 55, ports: [], at: old, interval: 60)
        store.flush()
        store.rollupAndPurge(now: now)
        store.flush()

        // 原始行已经挪走，但按 7 天窗口查询仍然能sum到
        let week = store.agentTotals(since: now - 7 * 86400)
        #expect(week.count == 1)
        #expect(abs(week[0].cpuSeconds - 60) < 0.001)
    }

    @Test("端口按出现次数累计")
    func 端口统计() throws {
        let (store, path) = tempStore()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let now = Int(Date().timeIntervalSince1970)

        for i in 0..<3 {
            store.record(agents: [], temp: nil, ports: [
                DevService(pid: 900, port: 5173, command: "node", uptime: 100, stray: false, cwd: "/tmp"),
            ], at: now - i * 60, interval: 60)
        }
        store.flush()

        let ports = store.portTotals(since: now - 3600)
        #expect(ports.count == 1)
        #expect(ports[0].port == 5173)
        #expect(ports[0].samples == 3)
    }
}
