import Foundation
import Darwin

/// 一个仍在监听端口、但启动者已经退出的开发服务
struct DevService: Identifiable, Equatable {
    let pid: Int32
    let port: Int
    let command: String
    let uptime: TimeInterval

    var id: Int32 { pid }

    var uptimeText: String {
        let h = Int(uptime) / 3600
        if h >= 1 { return "\(h) 小时" }
        return "\(Int(uptime) / 60) 分钟"
    }
}

/// 找「残留」的开发服务器：`npm run dev` 起来后终端关了，进程被 launchd 收养，端口一直占着。
/// 判定三条同时满足，避免把 redis / jellyfin / 系统 daemon 误报成残留。
enum PortScanner {

    /// 开发服务器常见命令（lsof 的命令名会被截到 9-15 字符）
    private static let devCommands = [
        "node", "python", "ruby", "php", "deno", "bun", "java",
        "vite", "next", "nuxt", "webpack", "uvicorn", "gunicorn",
        "flask", "django", "rails", "puma", "hugo", "jekyll",
    ]

    /// 这些端口的持有者大概率是长期服务，不提示
    private static let ignoreCommands = [
        "redis", "rapportd", "tailscaled", "jellyfin", "postgres", "mysqld",
        "mongod", "dockerd", "ollama", "sshd", "nginx",
    ]

    /// - Parameters:
    ///   - maxAge: 超过这个运行时长就不算「刚才不小心留下的」
    static func scan(maxAge: TimeInterval = 48 * 3600) -> [DevService] {
        guard let text = runLsof() else { return [] }

        var results: [DevService] = []
        var curPid: Int32 = 0
        var curCmd = ""
        var curPorts: Set<Int> = []

        func flush() {
            defer { curPorts.removeAll() }
            guard curPid > 0, !curPorts.isEmpty else { return }
            let base = (curCmd as NSString).lastPathComponent.lowercased()
            guard !ignoreCommands.contains(where: { base.contains($0) }) else { return }
            guard devCommands.contains(where: { base.contains($0) }) else { return }
            guard let ppid = parentPid(curPid), ppid == 1 else { return }
            guard let age = runTime(curPid), age < maxAge else { return }
            for p in curPorts where p >= 1024 {
                results.append(DevService(pid: curPid, port: p, command: base, uptime: age))
            }
        }

        for line in text.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                flush()
                curPid = Int32(value) ?? 0
                curCmd = ""
            case "c":
                curCmd = value
            case "n":
                if let p = parsePort(value) { curPorts.insert(p) }
            default:
                break
            }
        }
        flush()

        // 同一 pid 多个端口只留第一个，UI 一行一个
        var seen = Set<Int32>()
        return results
            .sorted { $0.port < $1.port }
            .filter { seen.insert($0.pid).inserted }
    }

    // MARK: - lsof

    /// 输出重定向到临时文件而不是 Pipe：命令行工具没有 RunLoop，
    /// readDataToEndOfFile 会一直等管道 EOF，实测卡满 120 秒零输出。
    /// （popen 在 Swift 里被标记 unavailable，只能用 Process。）
    private static func runLsof() -> String? {
        let path = NSTemporaryDirectory() + "hotpot-lsof-\(getpid()).txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: path) else { return nil }
        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        p.standardOutput = fh
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        fh.closeFile()

        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// "*:3000" / "127.0.0.1:5173" / "[::1]:8080"
    private static func parsePort(_ name: String) -> Int? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        return Int(name[name.index(after: colon)...])
    }

    // MARK: - 进程属性

    private static func parentPid(_ pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) > 0 else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }

    private static func runTime(_ pid: Int32) -> TimeInterval? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) > 0 else { return nil }
        let start = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return Date().timeIntervalSince1970 - start
    }
}
