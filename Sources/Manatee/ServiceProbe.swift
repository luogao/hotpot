import Foundation

/// 探一下这个端口到底是什么服务：只打 127.0.0.1，1 秒超时，探不到就当没有。
/// 用于端口详情里回答「这东西是干嘛的」—— Server 头 + HTML 特征都看。
enum ServiceProbe {

    static func detect(port: Int, bind: String = "") -> String? {
        // vite 默认只监听 ::1，打 127.0.0.1 会连不上
        let host: String
        switch bind {
        case "::1": host = "[::1]"
        case "", "*", "0.0.0.0", "::": host = "127.0.0.1"
        default: host = bind.contains(":") ? "[\(bind)]" : bind
        }
        guard let url = URL(string: "http://\(host):\(port)/") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        req.setValue(AppInfo.name, forHTTPHeaderField: "User-Agent")

        var out: String?
        let sem = DispatchSemaphore(value: 0)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.0
        config.waitsForConnectivity = false
        let task = URLSession(configuration: config).dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let h = resp as? HTTPURLResponse else { return }
            out = classify(headers: h, body: data)
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        task.cancel()
        return out
    }

    private static func classify(headers: HTTPURLResponse, body: Data?) -> String? {
        let server = (headers.value(forHTTPHeaderField: "Server") ?? "").lowercased()
        let powered = (headers.value(forHTTPHeaderField: "X-Powered-By") ?? "").lowercased()
        let blob = server + " " + powered

        let table: [(String, String)] = [
            ("vite", "Vite"),
            ("next", "Next.js"),
            ("uvicorn", "Uvicorn"),
            ("werkzeug", "Flask"),
            ("gunicorn", "Gunicorn"),
            ("django", "Django"),
            ("express", "Express"),
            ("nginx", "nginx"),
            ("caddy", "Caddy"),
            ("jetty", "Jetty"),
            ("tomcat", "Tomcat"),
            ("hypercorn", "Hypercorn"),
            ("deno", "Deno"),
            ("webpack", "webpack"),
        ]
        for (k, v) in table where blob.contains(k) { return v }

        // Vite 的 Server 头是空的，只能看 body 里的 /@vite/client
        if let body, let html = String(data: body.prefix(8192), encoding: .utf8) {
            if html.contains("/@vite/client") { return "Vite" }
            if html.contains("__next_data__") || html.contains("/_next/") { return "Next.js" }
            if let t = title(html) { return t }
        }
        return nil
    }

    private static func title(_ html: String) -> String? {
        guard let a = html.range(of: "<title", options: .caseInsensitive),
              let b = html.range(of: "</title>", options: .caseInsensitive,
                                 range: a.upperBound..<html.endIndex)
        else { return nil }
        var s = String(html[a.upperBound..<b.lowerBound])
        if let gt = s.firstIndex(of: ">") { s = String(s[s.index(after: gt)...]) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // 目录列表 / 错误页的标题没有信息量，不如不显示
        let junk: Set<String> = ["error response", "not found", "404 not found",
                                 "welcome to nginx!", "index of /", "400 bad request"]
        if junk.contains(s.lowercased()) { return nil }
        return s.count > 36 ? String(s.prefix(36)) + "…" : s
    }
}
