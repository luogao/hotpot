import Foundation

/// 记录每个会话最近 6 分钟的 CPU 采样，用来判断「连续满载」。
/// 只看瞬时值会把编译时的短暂 800% 当成异常，所以必须带时间窗。
final class SessionHistory {
    private struct Sample {
        let at: Date
        let cpu: Double
    }

    /// 保留窗口：要比判定窗口长，才能覆盖「刚好满 5 分钟」的情况
    private let keep: TimeInterval = 360
    /// 连续多久算异常
    let sustain: TimeInterval
    /// CPU% 阈值（100 = 一个核）
    let threshold: Double

    private var buckets: [Int32: [Sample]] = [:]

    init(threshold: Double = 200, sustain: TimeInterval = 300) {
        self.threshold = threshold
        self.sustain = sustain
    }

    func record(_ sessions: [AgentSession], at now: Date = Date()) {
        var alive = Set<Int32>()
        for s in sessions {
            alive.insert(s.rootPid)
            var list = buckets[s.rootPid] ?? []
            list.append(Sample(at: now, cpu: s.cpuPercent))
            list.removeAll { now.timeIntervalSince($0.at) > keep }
            buckets[s.rootPid] = list
        }
        // 会话消失后留 3 分钟再清，避免进程抖动导致预警闪烁
        let stale = buckets.compactMap { pid, list -> Int32? in
            guard !alive.contains(pid) else { return nil }
            guard let last = list.last else { return pid }
            return now.timeIntervalSince(last.at) > 180 ? pid : nil
        }
        for pid in stale { buckets.removeValue(forKey: pid) }
    }

    /// 连续超过阈值的时长（秒）。不足 sustain 返回 nil。
    func sustained(pid: Int32) -> TimeInterval? {
        guard let list = buckets[pid], list.count >= 2, let last = list.last else { return nil }
        var start: Date?
        for s in list.reversed() {
            if s.cpu >= threshold { start = s.at } else { break }
        }
        guard let start else { return nil }
        let dur = last.at.timeIntervalSince(start)
        return dur >= sustain ? dur : nil
    }

    /// 会话列表变化后，把已经不存在的 pid 的历史清掉（会话真的退出时立即清）
    func prune(keeping alive: Set<Int32>) {
        for pid in buckets.keys where !alive.contains(pid) {
            buckets.removeValue(forKey: pid)
        }
    }
}
