import Foundation
import Darwin

/// 一个监听本机端口的开发服务。`stray` 表示启动它的终端已经关了（被 launchd 收养）。
struct DevService: Identifiable, Equatable {
    let pid: Int32
    let port: Int
    let command: String
    let uptime: TimeInterval
    let stray: Bool

    var id: String { "\(pid):\(port)" }

    var uptimeText: String {
        let h = Int(uptime) / 3600
        if h >= 1 { return "\(h) 小时" }
        return "\(Int(uptime) / 60) 分钟"
    }
}

/// 列出所有开发服务占的端口：node / vite / python 这些命令在监听的都算。
/// 只提示「残留」会让人误以为功能没生效（终端还开着的时候什么都不显示），
/// 所以活跃的也列出来，残留的额外标一下、给关闭入口。
enum PortScanner {

    /// 开发服务器常见命令（lsof 的命令名会被截到 9-15 字符）
    private static var devCommands: [String] { Rules.shared.devServerCommands }

    /// 这些端口的持有者大概率是长期服务，不提示
    private static var ignoreCommands: [String] { Rules.shared.ignorePortCommands }

    /// - Parameter maxAge: 超过这个运行时长就不算「刚才不小心留下的」，但仍会列出（只是不标残留）
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
            let ppid = parentPid(curPid) ?? 0
            let age = runTime(curPid) ?? 0
            let stray = ppid == 1 && age < maxAge
            for p in curPorts where p >= 1024 {
                results.append(DevService(pid: curPid, port: p, command: base,
                                          uptime: age, stray: stray))
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

        // 同一端口只留一条；常见端口在前，调试端口（9229 等）靠后
        var seenPort = Set<Int>()
        return results
            .sorted { a, b in
                if a.stray != b.stray { return a.stray && !b.stray }
                return a.port < b.port
            }
            .filter { seenPort.insert($0.port).inserted }
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
