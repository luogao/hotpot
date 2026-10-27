import Foundation

/// 用户可编辑的规则表。第一次启动会在
/// `~/Library/Application Support/HotPot/rules.json` 写出一份，之后以文件为准。
/// 文件缺失或解析失败时回退到内置默认值，不让用户改坏 JSON 导致 app 起不来。
struct AgentRule: Codable {
    var id: String
    var name: String
    var symbol: String?
    var patterns: [String]
    var excludes: [String]?
    /// 设置页里的开关。旧文件没有这个字段时按启用处理。
    var enabled: Bool?
    /// 可执行名，**精确**比对 basename。两三个字母的名字（pi）靠 contains 会撞 pip / ping / python。
    var bin: String?
    /// 安装位置（支持 ~ 开头）。任一存在即视为「已安装」，设置页据此标注。
    var detect: [String]?
}

struct AlertRule: Codable {
    /// CPU% 阈值，100 = 一个核
    var cpuPercent: Double
    /// 连续多久算异常
    var sustainSeconds: Double
}

struct Rules: Codable {
    var version: Int
    var agents: [AgentRule]
    var devServerCommands: [String]
    var ignorePortCommands: [String]
    var alert: AlertRule

    static let path: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent(AppInfo.appSupportDir + "/rules.json")
    }()

    /// 设置页保存后要在进程内立即可读，所以是 var
    static var shared: Rules = load()

    // MARK: - 默认值

    static let `default` = Rules(
        version: 2,
        agents: [
            AgentRule(id: "claude", name: "Claude Code", symbol: "asterisk",
                      patterns: ["claude", ".claude/local"],
                      excludes: ["Claude.app", "Claude Helper", "claude.ai"], enabled: true, detect: ["~/.claude", "~/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]),
            AgentRule(id: "codex", name: "Codex CLI", symbol: "terminal",
                      patterns: ["codex"], excludes: ["Codex.app/Contents/Frameworks"], enabled: true, detect: ["~/.codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]),
            AgentRule(id: "cursor", name: "Cursor", symbol: "cursorarrow",
                      patterns: ["cursor-agent", "Cursor Helper (Renderer)"], excludes: [], enabled: true, detect: ["/Applications/Cursor.app", "~/.cursor"]),
            AgentRule(id: "gemini", name: "Gemini CLI", symbol: "sparkles",
                      patterns: ["gemini"], excludes: ["Gemini.app"], enabled: true, detect: ["~/.gemini", "/opt/homebrew/bin/gemini", "/usr/local/bin/gemini"]),
            AgentRule(id: "aider", name: "Aider", symbol: "curlybraces",
                      patterns: ["aider"], excludes: [], enabled: true, detect: ["~/.aider.conf.yml", "/opt/homebrew/bin/aider", "/usr/local/bin/aider"]),
            AgentRule(id: "copilot", name: "Copilot CLI", symbol: "person.crop.circle",
                      patterns: ["copilot"], excludes: [], enabled: true, detect: ["~/.copilot", "/opt/homebrew/bin/copilot", "/usr/local/bin/copilot"]),
            AgentRule(id: "pi", name: "Pi", symbol: "p.circle",
                      patterns: ["pi-coding-agent"], excludes: [],
                      enabled: true, bin: "pi",
                      detect: ["~/.pi/agent", "~/.bun/bin/pi", "~/.npm-global/bin/pi",
                               "/opt/homebrew/bin/pi", "/usr/local/bin/pi"]),
            AgentRule(id: "ollama", name: "Ollama", symbol: "circle.hexagongrid",
                      patterns: ["ollama"], excludes: [], enabled: true, detect: ["/Applications/Ollama.app", "/opt/homebrew/bin/ollama"]),
            AgentRule(id: "lmstudio", name: "LM Studio", symbol: "cube",
                      patterns: ["LM Studio", "lms "], excludes: [], enabled: true, detect: ["/Applications/LM Studio.app", "~/.lmstudio", "~/.cache/lm-studio"]),
            AgentRule(id: "xcode", name: "Xcode Build", symbol: "hammer",
                      patterns: ["xcodebuild", "swift-build", "swift-frontend", "clang"],
                      excludes: ["SourceKit", "clangd"], enabled: true, detect: ["/Applications/Xcode.app"]),
            AgentRule(id: "ffmpeg", name: "ffmpeg", symbol: "film",
                      patterns: ["ffmpeg"], excludes: [], enabled: true, detect: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]),
            AgentRule(id: "docker", name: "Docker", symbol: "shippingbox",
                      patterns: ["com.docker", "docker"], excludes: ["Docker Desktop"], enabled: true, detect: ["/Applications/Docker.app", "/usr/local/bin/docker", "~/.docker"]),
        ],
        devServerCommands: [
            "node", "python", "ruby", "php", "deno", "bun", "java",
            "vite", "next", "nuxt", "webpack", "uvicorn", "gunicorn",
            "flask", "django", "rails", "puma", "hugo", "jekyll",
        ],
        ignorePortCommands: [
            "redis", "rapportd", "tailscaled", "jellyfin", "postgres", "mysqld",
            "mongod", "dockerd", "ollama", "sshd", "nginx",
        ],
        alert: AlertRule(cpuPercent: 200, sustainSeconds: 300)
    )

    // MARK: - 读写

    static func load() -> Rules {
        let url = path
        guard let data = try? Data(contentsOf: url) else {
            writeDefault(to: url)
            return .default
        }
        do {
            var loaded = try JSONDecoder().decode(Rules.self, from: data)
            loaded.mergeNewAgents()
            loaded.migrateIfNeeded()
            return loaded
        } catch {
            // 用户改坏了：保留坏文件备份，回退默认，不覆盖他的编辑
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("rules.broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return .default
        }
    }

    /// 内置规则表新增了 agent（比如 Pi）时，老用户的 rules.json 里没有它。
    /// 按 id 补进去，用户自己的条目和开关状态一律不动。
    /// 内置图标 / 字段升级：version 2 起统一用新的 symbol 名（Aider 的 `</>` 太宽）。
    /// 只覆盖 symbol，用户的 patterns / excludes / enabled 一律不动。
    mutating func migrateIfNeeded() {
        guard version < 2 else { return }
        let defaults = Dictionary(uniqueKeysWithValues: Rules.default.agents.map { ($0.id, $0) })
        for i in agents.indices {
            if let d = defaults[agents[i].id], let sym = d.symbol {
                agents[i].symbol = sym
            }
        }
        version = 2
    }

    mutating func mergeNewAgents() {
        let known = Set(agents.map(\.id))
        for d in Rules.default.agents where !known.contains(d.id) {
            agents.append(d)
        }
    }

    private static func writeDefault(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(Rules.default) {
            try? data.write(to: url)
        }
    }

    /// 把当前内存里的规则写回文件（用户点了「恢复默认」时用）
    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Rules.path)
        }
    }
}
