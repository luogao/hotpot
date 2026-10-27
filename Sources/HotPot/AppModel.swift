import Foundation
import AppKit

final class AppModel: ObservableObject {

    @Published var temperature: Double = 0
    @Published var sensorName: String = ""
    @Published var sessions: [AgentSession] = []
    @Published var cooled: Set<pid_t> = []
    @Published var processCount: Int = 0
    @Published var lastError: String?
    /// 面板是否展开：关着的时候只需要刷新菜单栏温度，不用每 2 秒扫全表
    var panelOpen = false

    private let scanner = ProcessScanner()
    private let temp = TemperatureReader()
    private let queue = DispatchQueue(label: "whoiscooking.scan", qos: .utility)
    private var timer: Timer?
    private var warming = true

    func start() {
        _ = scanner.scan()               // 建基线
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// 同步跑一次（给离屏渲染/自检用）
    func loadSync() {
        _ = scanner.scan()
        Thread.sleep(forTimeInterval: 1.0)
        let procs = scanner.scan()
        sessions = SessionAggregator.build(from: procs)
        processCount = procs.count
        if let hot = temp?.hottestSilicon() ?? temp?.hottestAny() {
            temperature = hot.celsius
            sensorName = hot.name
        }
    }

    private var tickCount = 0

    private func tick() {
        tickCount += 1
        // 温度 ~25ms，扫描 ~13ms：温度每 3 拍（6 秒）一次；面板关着时 10 秒才扫一次
        let needTemp = (tickCount % 3 == 1)
        let needScan = panelOpen || (tickCount % 5 == 1)
        guard needTemp || needScan else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let procs = needScan ? self.scanner.scan() : []
            let sessions = needScan ? SessionAggregator.build(from: procs) : self.sessions
            let hot = needTemp ? (self.temp?.hottestSilicon() ?? self.temp?.hottestAny()) : nil
            DispatchQueue.main.async {
                if let hot {
                    self.temperature = hot.celsius
                    self.sensorName = hot.name
                }
                if needScan { self.processCount = procs.count }
                self.sessions = sessions
                // 清掉已退出进程的降温标记
                let alive = Set(procs.map(\.pid))
                self.cooled.formIntersection(alive)
                self.lastError = self.temp == nil ? "温度传感器不可用" : nil
            }
        }
    }

    func isCooled(_ s: AgentSession) -> Bool {
        s.pids.contains { cooled.contains($0) }
    }

    func toggleCool(_ s: AgentSession) {
        if isCooled(s) {
            Cooler.restore(pids: s.pids)
            cooled.subtract(s.pids)
        } else {
            let ok = Cooler.cool(pids: s.pids)
            cooled.formUnion(ok)
        }
    }

    func coolAll() {
        let all = sessions.flatMap(\.pids).filter { !cooled.contains($0) }
        let ok = Cooler.cool(pids: all)
        cooled.formUnion(ok)
    }

    func restoreAll() {
        Cooler.restore(pids: Array(cooled))
        cooled.removeAll()
    }

    /// 温度分档：给状态栏和面板用同一套阈值
    var level: HeatLevel {
        switch temperature {
        case ..<55: return .cool
        case ..<70: return .warm
        case ..<85: return .hot
        default: return .critical
        }
    }
}

enum HeatLevel {
    case cool, warm, hot, critical
    var label: String {
        switch self {
        case .cool: return "凉"
        case .warm: return "温热"
        case .hot: return "烫"
        case .critical: return "过热降频"
        }
    }
    var color: NSColor {
        switch self {
        case .cool: return NSColor(red: 0.15, green: 0.55, blue: 0.45, alpha: 1)
        case .warm: return NSColor(red: 0.85, green: 0.60, blue: 0.15, alpha: 1)
        case .hot: return NSColor(red: 0.88, green: 0.35, blue: 0.15, alpha: 1)
        case .critical: return NSColor(red: 0.80, green: 0.12, blue: 0.12, alpha: 1)
        }
    }
}
