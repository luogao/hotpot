import Foundation

struct AgentDef {
    let id: String
    let name: String
    let emoji: String
    /// 命中任一即认为是该 agent 的主进程
    let patterns: [String]
    /// 命中任一则排除（避免把 IDE 的渲染进程当成 agent 本体）
    let excludes: [String]
}

/// 对齐原产品支持列表，可在此扩展
enum AgentRegistry {
    static let all: [AgentDef] = [
        AgentDef(id: "claude", name: "Claude Code", emoji: "🟠",
                 patterns: ["claude", ".claude/local"],
                 excludes: ["Claude.app", "Claude Helper", "claude.ai"]),
        AgentDef(id: "codex", name: "Codex CLI", emoji: "⚫️",
                 patterns: ["codex"],
                 excludes: ["Codex.app/Contents/Frameworks"]),
        AgentDef(id: "cursor", name: "Cursor", emoji: "🔵",
                 patterns: ["cursor-agent", "Cursor Helper (Renderer)"],
                 excludes: []),
        AgentDef(id: "gemini", name: "Gemini CLI", emoji: "🔷",
                 patterns: ["gemini"], excludes: ["Gemini.app"]),
        AgentDef(id: "aider", name: "Aider", emoji: "🟢",
                 patterns: ["aider"], excludes: []),
        AgentDef(id: "copilot", name: "Copilot CLI", emoji: "⚪️",
                 patterns: ["copilot"], excludes: []),
        AgentDef(id: "ollama", name: "Ollama", emoji: "🦙",
                 patterns: ["ollama"], excludes: []),
        AgentDef(id: "lmstudio", name: "LM Studio", emoji: "🟣",
                 patterns: ["LM Studio", "lms "], excludes: []),
        AgentDef(id: "xcode", name: "Xcode Build", emoji: "🔨",
                 patterns: ["xcodebuild", "swift-build", "swift-frontend", "clang"],
                 excludes: ["SourceKit", "clangd"]),
        AgentDef(id: "ffmpeg", name: "ffmpeg", emoji: "🎬",
                 patterns: ["ffmpeg"], excludes: []),
        AgentDef(id: "docker", name: "Docker", emoji: "🐳",
                 patterns: ["com.docker", "docker"], excludes: ["Docker Desktop"]),
    ]

    static func match(_ p: ProcInfo) -> AgentDef? {
        let base = (p.path as NSString).lastPathComponent.lowercased()
        let args = p.args.lowercased()

        // 噪声：崩溃上报、Electron 辅助进程、框架内部进程一律不参与归因
        // 注意 comm 只有 15 字节，"browser_crashpad" 会被截成 "browser_crashpa"，所以用 crash
        let noise = ["crash", "helper", "framework", "xpcservice", "webcontent"]
        if noise.contains(where: { base.contains($0) }) { return nil }
        // IDE 里跑的扩展进程（Copilot SDK）不算 CLI agent
        if base.contains("code helper") || args.contains("visual studio code.app") { return nil }

        let hay = base + " " + args
        for d in all {
            if d.excludes.contains(where: { hay.contains($0.lowercased()) }) { continue }
            if d.patterns.contains(where: { hay.contains($0.lowercased()) }) { return d }
        }
        return nil
    }
}

struct AgentSession {
    let def: AgentDef
    let rootPid: pid_t
    var cpuPercent: Double
    var pids: [pid_t]
    var busyChildren: [(name: String, cpu: Double)]
    var cooled: Bool
    var hasOtherUid: Bool

    var summary: String {
        if busyChildren.isEmpty { return "idle" }
        return "running: " + busyChildren.prefix(3).map { $0.name }.joined(separator: ", ")
    }
}

enum SessionAggregator {

    /// 把进程表压成「一个 agent 会话一行」
    static func build(from procs: [ProcInfo]) -> [AgentSession] {
        let byPid = Dictionary(uniqueKeysWithValues: procs.map { ($0.pid, $0) })

        // 1) 找出所有命中规则的进程
        var matched: [pid_t: AgentDef] = [:]
        for p in procs {
            if let d = AgentRegistry.match(p) { matched[p.pid] = d }
        }
        guard !matched.isEmpty else { return [] }

        // 2) 只保留「最上层」的命中进程作为会话根，避免父子重复
        func hasMatchedAncestor(_ pid: pid_t) -> Bool {
            var cur = pid
            var depth = 0
            while let p = byPid[cur], p.ppid > 1, depth < 40 {
                if matched[p.ppid] != nil { return true }
                cur = p.ppid
                depth += 1
            }
            return false
        }
        let roots = matched.keys.filter { !hasMatchedAncestor($0) }

        // 3) 每个进程归给最近的根（先走 ppid 链，再按 pgid 兜底）
        var owner: [pid_t: pid_t] = [:]
        func findOwner(_ pid: pid_t) -> pid_t? {
            var cur = pid
            var depth = 0
            while depth < 40 {
                if roots.contains(cur) { return cur }
                guard let p = byPid[cur], p.ppid > 1 else { break }
                cur = p.ppid
                depth += 1
            }
            return nil
        }
        var pgidRoot: [pid_t: pid_t] = [:]
        for r in roots { if let p = byPid[r] { pgidRoot[p.pgid] = r } }

        for p in procs {
            if let o = findOwner(p.pid) {
                owner[p.pid] = o
            } else if let r = pgidRoot[p.pgid] {
                owner[p.pid] = r
            }
        }

        // 4) 汇总
        var acc: [pid_t: (cpu: Double, pids: [pid_t], kids: [(String, Double)], otherUid: Bool)] = [:]
        for p in procs {
            guard let o = owner[p.pid] else { continue }
            var e = acc[o] ?? (0, [], [], false)
            e.cpu += p.cpuPercent
            e.pids.append(p.pid)
            if p.cpuPercent >= 3, p.pid != o {
                e.kids.append((shortName(p), p.cpuPercent))
            }
            if p.otherUid { e.otherUid = true }
            acc[o] = e
        }

        return roots.compactMap { r -> AgentSession? in
            guard let d = matched[r], let e = acc[r] else { return nil }
            return AgentSession(
                def: d,
                rootPid: r,
                cpuPercent: (e.cpu * 10).rounded() / 10,
                pids: e.pids.sorted(),
                busyChildren: e.kids.sorted { $0.1 > $1.1 },
                cooled: false,
                hasOtherUid: e.otherUid
            )
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    static func shortName(_ p: ProcInfo) -> String {
        let base = (p.path as NSString).lastPathComponent
        if base.hasPrefix("node"), let first = p.args.split(separator: " ").dropFirst().first {
            return (String(first) as NSString).lastPathComponent
        }
        return base
    }
}
