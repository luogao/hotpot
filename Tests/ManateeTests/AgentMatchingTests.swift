import Testing
import Foundation
@testable import Manatee

/// 测试用的规则表：不复用用户本地的 rules.json，避免测试随配置漂移
private let testRules: [AgentDef] = [
    AgentDef(id: "claude", name: "Claude Code", symbol: "asterisk",
             patterns: ["claude", ".claude/local"],
             excludes: ["Claude.app", "Claude Helper", "claude.ai"],
             bin: nil, detect: []),
    AgentDef(id: "pi", name: "Pi", symbol: "p.circle",
             patterns: ["pi-coding-agent"], excludes: [],
             bin: "pi", detect: []),
    AgentDef(id: "ffmpeg", name: "ffmpeg", symbol: "film",
             patterns: ["ffmpeg"], excludes: [], bin: nil, detect: []),
    AgentDef(id: "docker", name: "Docker", symbol: "shippingbox",
             patterns: ["com.docker", "docker"], excludes: ["Docker Desktop"],
             bin: nil, detect: []),
]

private func proc(_ path: String, args: String = "",
                  pid: pid_t = 100, ppid: pid_t = 1, pgid: pid_t? = nil) -> ProcInfo {
    ProcInfo(pid: pid, ppid: ppid, pgid: pgid ?? pid, uid: 501,
             comm: (path as NSString).lastPathComponent,
             path: path, args: args)
}

private func match(_ path: String, args: String = "") -> String? {
    AgentRegistry.match(proc(path, args: args), rules: testRules)?.id
}

@Suite("Agent 识别")
struct AgentMatchingTests {

    @Test("CLI 直接运行：按命令行命中")
    func 直接命中() {
        #expect(match("/Users/x/.claude/local/claude", args: "claude") == "claude")
        #expect(match("/opt/homebrew/bin/ffmpeg", args: "ffmpeg -i a.mp4") == "ffmpeg")
    }

    @Test("pi 走精确 basename，不被 ping 误伤")
    func pi精确匹配() {
        #expect(match("/Users/x/.bun/bin/pi", args: "pi") == "pi")
        // ping 的 basename 是 ping，patterns 里也没有 pi 的子串规则
        #expect(match("/sbin/ping", args: "ping -c 1 8.8.8.8") == nil)
    }

    @Test("node 跑脚本时按参数里的脚本名认 pi")
    func node脚本归属() {
        #expect(match("/opt/homebrew/bin/node",
                      args: "node /Users/x/.bun/bin/pi --resume") == "pi")
    }

    @Test("排除规则：Claude 桌面端不算 CLI")
    func 排除桌面端() {
        #expect(match("/Applications/Claude.app/Contents/MacOS/Claude") == nil)
        #expect(match("/Applications/Claude.app/Contents/Frameworks/Claude Helper") == nil)
    }

    @Test("噪声进程不参与归因")
    func 噪声排除() {
        #expect(match("/Applications/X.app/Contents/Frameworks/Electron Framework.framework/crashpad") == nil)
        #expect(match("/Applications/Visual Studio Code.app/Contents/MacOS/Code Helper") == nil)
    }

    @Test("Docker Desktop 主进程被排除，docker CLI 保留")
    func docker排除() {
        #expect(match("/Applications/Docker.app/Contents/MacOS/Docker Desktop") == nil)
        #expect(match("/usr/local/bin/docker", args: "docker ps") == "docker")
    }
}
