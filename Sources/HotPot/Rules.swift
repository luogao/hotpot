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
        return base.appendingPathComponent("HotPot/rules.json")
    }()

    /// 设置页保存后要在进程内立即可读，所以是 var
    static var shared: Rules = load()

    // MARK: - 默认值

    static let `default` = Rules(
        version: 1,
        agents: [
            AgentRule(id: "claude", name: "Claude Code", symbol: "asterisk",
                      patterns: ["claude", ".claude/local"],
                      excludes: ["Claude.app", "Claude Helper", "claude.ai"], enabled: true),
            AgentRule(id: "codex", name: "Codex CLI", symbol: "terminal",
                      patterns: ["codex"], excludes: ["Codex.app/Contents/Frameworks"], enabled: true),
            AgentRule(id: "cursor", name: "Cursor", symbol: "cursorarrow",
                      patterns: ["cursor-agent", "Cursor Helper (Renderer)"], excludes: [], enabled: true),
            AgentRule(id: "gemini", name: "Gemini CLI", symbol: "sparkles",
                      patterns: ["gemini"], excludes: ["Gemini.app"], enabled: true),
            AgentRule(id: "aider", name: "Aider", symbol: "chevron.left.forwardslash.chevron.right",
                      patterns: ["aider"], excludes: [], enabled: true),
            AgentRule(id: "copilot", name: "Copilot CLI", symbol: "person.crop.circle",
                      patterns: ["copilot"], excludes: [], enabled: true),
            AgentRule(id: "ollama", name: "Ollama", symbol: "circle.hexagongrid",
                      patterns: ["ollama"], excludes: [], enabled: true),
            AgentRule(id: "lmstudio", name: "LM Studio", symbol: "cube",
                      patterns: ["LM Studio", "lms "], excludes: [], enabled: true),
            AgentRule(id: "xcode", name: "Xcode Build", symbol: "hammer",
                      patterns: ["xcodebuild", "swift-build", "swift-frontend", "clang"],
                      excludes: ["SourceKit", "clangd"], enabled: true),
            AgentRule(id: "ffmpeg", name: "ffmpeg", symbol: "film",
                      patterns: ["ffmpeg"], excludes: [], enabled: true),
            AgentRule(id: "docker", name: "Docker", symbol: "shippingbox",
                      patterns: ["com.docker", "docker"], excludes: ["Docker Desktop"], enabled: true),
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
            return try JSONDecoder().decode(Rules.self, from: data)
        } catch {
            // 用户改坏了：保留坏文件备份，回退默认，不覆盖他的编辑
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("rules.broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return .default
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
