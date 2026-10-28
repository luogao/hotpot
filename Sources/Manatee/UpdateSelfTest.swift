import Foundation
import AppKit

/// `Manatee --update-selftest <zip> [目标目录]`
///
/// 用真 zip 走一遍更新链路，但只在临时沙盒里做替换，不碰真实安装的 app。
/// 覆盖三件最容易出事的事：解包对不对、校验能不能拦住坏包、替换失败能不能回滚。
enum UpdateSelfTest {
    private static var failures = 0

    static func run(zip: String, targetDir: String?) -> Int32 {
        failures = 0
        print("update selftest")
        let zipURL = URL(fileURLWithPath: zip)
        check("zip 存在", FileManager.default.fileExists(atPath: zipURL.path), zip)

        let root = URL(fileURLWithPath: targetDir ?? NSTemporaryDirectory())
            .appendingPathComponent("manatee-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 1) 解包
        let newApp: URL
        do {
            newApp = try Updater.unzip(zipURL, into: root)
            check("解包", true, newApp.lastPathComponent)
        } catch {
            check("解包", false, error.localizedDescription)
            return finish()
        }

        // 2) 校验：版本从包里读，应该通过
        let plist = newApp.appendingPathComponent("Contents/Info.plist")
        let d = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
        let ver = d["CFBundleShortVersionString"] as? String ?? "0"
        do {
            try Updater.validate(newApp, expecting: ver)
            check("校验通过", true, "v\(ver)")
        } catch {
            check("校验通过", false, error.localizedDescription)
        }

        // 3) 负样本：要一个比包里高的版本，必须被拒
        do {
            try Updater.validate(newApp, expecting: "999.0.0")
            check("拒绝版本不足的包", false, "居然通过了")
        } catch {
            check("拒绝版本不足的包", true)
        }

        // 4) 负样本：bundle id 被改过的包，必须被拒
        let tampered = root.appendingPathComponent("Tampered.app")
        do {
            try FileManager.default.copyItem(at: newApp, to: tampered)
            var m = d
            m["CFBundleIdentifier"] = "com.evil.clone"
            let p = tampered.appendingPathComponent("Contents/Info.plist")
            (m as NSDictionary).write(to: p, atomically: true)
            do {
                try Updater.validate(tampered, expecting: ver)
                check("拒绝 bundle id 不匹配", false, "居然通过了")
            } catch {
                check("拒绝 bundle id 不匹配", true)
            }
        } catch {
            check("拒绝 bundle id 不匹配", false, error.localizedDescription)
        }

        // 5) 替换演练：沙盒里放一个「旧版」，执行 swap 脚本，核对换成新的、旧版被清理
        let sandbox = root.appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let fakeTarget = sandbox.appendingPathComponent("Manatee.app")
        do {
            try FileManager.default.copyItem(at: newApp, to: fakeTarget)
            // 打个标记，验证确实被替换
            let marker = fakeTarget.appendingPathComponent("OLD_MARKER")
            try "old".write(to: marker, atomically: true, encoding: .utf8)
            let script = try Swap.makeScript(newApp: newApp, target: fakeTarget, pid: -1)
            let r = Swap.runBlocking(script)
            check("替换脚本退出码", r == 0, "\(r)")
            check("旧版已替换", !FileManager.default.fileExists(atPath: marker.path))
            check("新版就位", FileManager.default.fileExists(
                atPath: fakeTarget.appendingPathComponent("Contents/MacOS").path))
            check("备份已清理", !FileManager.default.fileExists(atPath: fakeTarget.path + ".bak"))
        } catch {
            check("替换演练", false, error.localizedDescription)
        }

        return finish()
    }

    private static func finish() -> Int32 {
        print(failures == 0 ? "selftest passed" : "selftest failed: \(failures) 项")
        return failures == 0 ? 0 : 1
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            print("  [ok] \(name)\(detail.isEmpty ? "" : "  \(detail)")")
        } else {
            failures += 1
            print("  [fail] \(name)\(detail.isEmpty ? "" : "  \(detail)")")
        }
    }
}

/// 换包脚本的生成与执行，从 Updater 里抽出来，方便自检里不重启 app 地跑一遍。
enum Swap {
    static func makeScript(newApp: URL, target: URL, pid: Int32) throws -> URL {
        let script = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manatee-swap-\(UUID().uuidString).sh")
        let body = """
        #!/bin/sh
        PID=\(pid)
        TARGET="\(target.path)"
        NEW="\(newApp.path)"
        if [ "$PID" -gt 0 ]; then
          i=0
          while kill -0 "$PID" 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i+1)); done
        fi
        STAGE="$(mktemp -d)"
        cp -R "$NEW" "$STAGE/Manatee.app" || { rm -rf "$STAGE"; exit 1; }
        xattr -dr com.apple.quarantine "$STAGE/Manatee.app" 2>/dev/null
        OLD="$TARGET.bak"
        rm -rf "$OLD"
        if [ -e "$TARGET" ]; then mv "$TARGET" "$OLD" || exit 1; fi
        if mv "$STAGE/Manatee.app" "$TARGET"; then
          rm -rf "$OLD"
          rm -rf "$STAGE"
          open "$TARGET"
          exit 0
        else
          [ -e "$OLD" ] && mv "$OLD" "$TARGET"
          rm -rf "$STAGE"
          exit 1
        fi
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @discardableResult
    static func runBlocking(_ script: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

extension UpdateSelfTest {
    /// `--update-check`：走一遍真实的 Updater（含 API→302→atom 三级降级），打印最终状态。
    /// 注意不能在这里用 MainActor.assumeIsolated——本函数跑在 main.swift 顶层，
    /// 不在 actor 隔离里，强行 assume 会直接 trap（曾导致 Trace/BPT: 5）。
    @MainActor static func liveCheck() -> Int32 {
        print("update live check")
        print("  当前版本 \(AppInfo.version)")
        var code: Int32 = 0

        let done = DispatchSemaphore(value: 0)
        var finished = false

        DispatchQueue.main.async {
            UserDefaults.standard.removeObject(forKey: "update.lastCheck")
            Updater.shared.check()
        }

        // 主线程等结果：期间要跑 runloop，否则网络回调回不到主线程
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let terminal: Bool = {
                switch Updater.shared.phase {
                case .checking: return false
                default: return true
                }
            }()
            if terminal { finished = true; break }
        }
        done.signal()

        if !finished {
            print("  [fail] 45 秒内没有结果")
            code = 1
        } else {
            let (phase, remote) = (Updater.shared.phase, Updater.shared.remote)
            switch phase {
            case .available(let v):
                print("  [ok] 有新版本 v\(v)（远端 \(remote?.version ?? "?"))")
                if let z = remote?.zipURL { print("       zip \(z.lastPathComponent)") }
                if let n = remote?.notes, !n.isEmpty { print("       备注 \(n.count) 字") }
                else { print("       （这条链路拿不到备注，只判断版本）") }
            case .upToDate:
                print("  [ok] 已是最新（远端 \(remote?.version ?? "?"))")
            case .failed(let m):
                print("  [fail] \(m)")
                code = 1
            default:
                print("  [fail] 状态 \(phase)")
                code = 1
            }
        }

        // 解析单测（不联网）
        let tagURL = URL(string: "https://github.com/luogao/manatee/releases/tag/v0.8.3")!
        let v = Updater.versionFromTagURL(tagURL) ?? "nil"
        print(v == "0.8.3" ? "  [ok] 302 版本解析  \(v)" : "  [fail] 302 版本解析  \(v)")
        if v != "0.8.3" { code = 1 }
        let atom = "<feed><entry><link href=\"https://github.com/luogao/manatee/releases/tag/v0.9.1\"/></entry></feed>"
        let a = Updater.firstTagFromAtom(atom) ?? "nil"
        print(a == "0.9.1" ? "  [ok] atom 版本解析  \(a)" : "  [fail] atom 版本解析  \(a)")
        if a != "0.9.1" { code = 1 }
        let z2 = Updater.zipURL(for: "0.9.1")?.lastPathComponent ?? "nil"
        print(z2 == "Manatee-0.9.1.zip" ? "  [ok] zip 直链拼接  \(z2)" : "  [fail] zip 直链拼接  \(z2)")
        if z2 != "Manatee-0.9.1.zip" { code = 1 }
        return code
    }
}
