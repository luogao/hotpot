import Foundation
import SQLite3

/// 资源看板的存储层：SQLite 单文件，所有读写走一条串行队列。
/// 设计说明见 docs/DASHBOARD.md。
final class MetricsStore {

    static let shared = MetricsStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "manatee.metrics", qos: .utility)
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    var dbPath: String { path }

    private let path: String

    private init() {
        path = Self.defaultPath()
        queue.sync { open() }
    }

    /// 测试用：独立数据库文件
    init(path: String) {
        self.path = path
        queue.sync { open() }
    }

    private static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["HOTPOT_METRICS_DB"] { return override }
        return (AppInfo.supportPath as NSString).appendingPathComponent("metrics.sqlite")
    }

    // MARK: - 打开 / 建表

    private func open() {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA busy_timeout=2000;")
        exec("""
        CREATE TABLE IF NOT EXISTS samples (
          ts INTEGER NOT NULL, agent TEXT NOT NULL,
          cpu_seconds REAL NOT NULL, mem_mb REAL NOT NULL, procs INTEGER NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts);")
        exec("CREATE INDEX IF NOT EXISTS idx_samples_agent ON samples(agent, ts);")
        exec("CREATE TABLE IF NOT EXISTS temps (ts INTEGER PRIMARY KEY, celsius REAL NOT NULL);")
        exec("CREATE TABLE IF NOT EXISTS ports (ts INTEGER NOT NULL, port INTEGER NOT NULL, command TEXT NOT NULL, pid INTEGER NOT NULL, cwd TEXT);")
        exec("CREATE INDEX IF NOT EXISTS idx_ports_ts ON ports(ts);")
        exec("""
        CREATE TABLE IF NOT EXISTS samples_hourly (
          hour INTEGER NOT NULL, agent TEXT NOT NULL,
          cpu_seconds REAL NOT NULL, procs_peak INTEGER NOT NULL,
          PRIMARY KEY (hour, agent)
        );
        """)
        exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);")
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - 写入

    /// 一次采样。`interval` 是距上次采样的秒数，用来把百分比折算成 CPU 秒。
    func record(agents: [(id: String, cpuPercent: Double, memMB: Double, procs: Int)],
                temp: Double?,
                ports: [DevService],
                at ts: Int,
                interval: Double) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            self.exec("BEGIN;")
            let sql = "INSERT INTO samples (ts, agent, cpu_seconds, mem_mb, procs) VALUES (?,?,?,?,?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for a in agents {
                    let cpuSeconds = max(0, a.cpuPercent) / 100.0 * interval
                    sqlite3_bind_int64(stmt, 1, Int64(ts))
                    sqlite3_bind_text(stmt, 2, a.id, -1, self.SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 3, cpuSeconds)
                    sqlite3_bind_double(stmt, 4, a.memMB)
                    sqlite3_bind_int(stmt, 5, Int32(a.procs))
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)

            if let temp {
                var tstmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO temps (ts, celsius) VALUES (?,?);", -1, &tstmt, nil) == SQLITE_OK {
                    sqlite3_bind_int64(tstmt, 1, Int64(ts))
                    sqlite3_bind_double(tstmt, 2, temp)
                    sqlite3_step(tstmt)
                }
                sqlite3_finalize(tstmt)
            }

            if !ports.isEmpty {
                var pstmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "INSERT INTO ports (ts, port, command, pid, cwd) VALUES (?,?,?,?,?);", -1, &pstmt, nil) == SQLITE_OK {
                    for p in ports {
                        sqlite3_bind_int64(pstmt, 1, Int64(ts))
                        sqlite3_bind_int(pstmt, 2, Int32(p.port))
                        sqlite3_bind_text(pstmt, 3, p.command, -1, self.SQLITE_TRANSIENT)
                        sqlite3_bind_int(pstmt, 4, Int32(p.pid))
                        sqlite3_bind_text(pstmt, 5, p.cwd, -1, self.SQLITE_TRANSIENT)
                        sqlite3_step(pstmt)
                        sqlite3_reset(pstmt)
                    }
                }
                sqlite3_finalize(pstmt)
            }
            self.exec("COMMIT;")
        }
    }

    // MARK: - 查询

    struct AgentTotal {
        let agent: String
        let cpuSeconds: Double
    }

    struct TempPoint {
        let ts: Int
        let celsius: Double
    }

    struct PortTotal {
        let port: Int
        let command: String
        let samples: Int
    }

    struct Summary {
        var cpuSeconds: Double = 0
        var peakTemp: Double = 0
        var agents: Int = 0
        var sessions: Int = 0
    }

    /// since 之前的原始数据 + 更早的小时聚合，统一成 agent 维度的累计 CPU 秒
    func agentTotals(since: Int) -> [AgentTotal] {
        queue.sync {
            guard let db else { return [] }
            var out: [AgentTotal] = []
            let sql = """
            SELECT agent, SUM(cpu_seconds) AS c FROM (
              SELECT agent, cpu_seconds FROM samples_hourly WHERE hour >= ?
              UNION ALL
              SELECT agent, cpu_seconds FROM samples WHERE ts >= ?
            ) GROUP BY agent ORDER BY c DESC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int64(stmt, 1, Int64(since))
            sqlite3_bind_int64(stmt, 2, Int64(since))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                out.append(AgentTotal(agent: id, cpuSeconds: sqlite3_column_double(stmt, 1)))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    /// bucket > 1 时按桶取平均，避免 24 小时两千个点画成毛刺
    func temps(since: Int, bucket: Int = 1) -> [TempPoint] {
        queue.sync {
            guard let db else { return [] }
            var out: [TempPoint] = []
            let sql = bucket <= 1
                ? "SELECT ts, celsius FROM temps WHERE ts >= ? ORDER BY ts;"
                : "SELECT (ts / ?) * ? AS b, AVG(celsius) FROM temps WHERE ts >= ? GROUP BY b ORDER BY b;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            if bucket <= 1 {
                sqlite3_bind_int64(stmt, 1, Int64(since))
            } else {
                sqlite3_bind_int64(stmt, 1, Int64(bucket))
                sqlite3_bind_int64(stmt, 2, Int64(bucket))
                sqlite3_bind_int64(stmt, 3, Int64(since))
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(TempPoint(ts: Int(sqlite3_column_int64(stmt, 0)),
                                     celsius: sqlite3_column_double(stmt, 1)))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func portTotals(since: Int) -> [PortTotal] {
        queue.sync {
            guard let db else { return [] }
            var out: [PortTotal] = []
            let sql = """
            SELECT port, command, COUNT(*) AS n FROM ports
            WHERE ts >= ? GROUP BY port, command ORDER BY n DESC LIMIT 12;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int64(stmt, 1, Int64(since))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(PortTotal(port: Int(sqlite3_column_int(stmt, 0)),
                                     command: String(cString: sqlite3_column_text(stmt, 1)),
                                     samples: Int(sqlite3_column_int(stmt, 2))))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func summary(since: Int) -> Summary {
        var s = Summary()
        let totals = agentTotals(since: since)   // 只查一次，别在 summary 里重复扫
        s.cpuSeconds = totals.reduce(0) { $0 + $1.cpuSeconds }
        s.agents = totals.count
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT MAX(celsius) FROM temps WHERE ts >= ?;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(since))
                if sqlite3_step(stmt) == SQLITE_ROW { s.peakTemp = sqlite3_column_double(stmt, 0) }
            }
            sqlite3_finalize(stmt)
        }
        return s
    }

    // MARK: - 维护

    /// 2 天前的原始数据压成小时表，再删原始行；90 天前的小时数据删掉
    func rollupAndPurge(now: Int = Int(Date().timeIntervalSince1970)) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let cutoff = now - 48 * 3600
            self.exec("""
            INSERT INTO samples_hourly (hour, agent, cpu_seconds, procs_peak)
            SELECT (ts / 3600) * 3600, agent, SUM(cpu_seconds), MAX(procs)
            FROM samples WHERE ts < \(cutoff)
            GROUP BY (ts / 3600) * 3600, agent
            ON CONFLICT(hour, agent) DO UPDATE SET
              cpu_seconds = cpu_seconds + excluded.cpu_seconds,
              procs_peak = MAX(procs_peak, excluded.procs_peak);
            """)
            self.exec("DELETE FROM samples WHERE ts < \(cutoff);")
            self.exec("DELETE FROM temps WHERE ts < \(now - 90 * 86400);")
            self.exec("DELETE FROM ports WHERE ts < \(now - 7 * 86400);")
            self.exec("DELETE FROM samples_hourly WHERE hour < \(now - 90 * 86400);")
            _ = db
        }
    }

    /// 等队列里排着的写入落盘（测试 / 退出前用）
    func flush() { queue.sync {} }

    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.exec("DELETE FROM samples; DELETE FROM temps; DELETE FROM ports; DELETE FROM samples_hourly; VACUUM;")
        }
    }

    func isEmpty() -> Bool {
        queue.sync {
            guard let db else { return true }
            var stmt: OpaquePointer?
            var empty = true
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM samples LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW { empty = sqlite3_column_int(stmt, 0) == 0 }
            }
            sqlite3_finalize(stmt)
            return empty
        }
    }
}
