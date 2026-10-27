import Foundation

/// 读 Apple Silicon 芯片温度。
/// 走 IOHIDEventSystemClient 私有符号，免 sudo、免 entitlement。
/// 注意：私有 API，不能上 Mac App Store；macOS 大版本升级可能改传感器命名，需容错。
final class TemperatureReader {

    private typealias CreateT      = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias CopyServicesT = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropT    = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventT   = @convention(c) (CFTypeRef, Int64, Int64, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatT    = @convention(c) (CFTypeRef, Int64) -> Double

    private var create: CreateT?
    private var copyServices: CopyServicesT?
    private var copyProperty: CopyPropT?
    private var copyEvent: CopyEventT?
    private var getFloat: GetFloatT?
    private var client: CFTypeRef?

    /// 已知 CPU/SOC 裸片传感器前缀（PMU tdie / PMU2 tdie / SOC MCPU 等）
    private let cpuSensorPrefixes = ["PMU tdie", "PMU2 tdie", "SOC MCPU", "SOC PCPU", "Tp0", "Tp1"]

    init?() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func sym<T>(_ n: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, n) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let c = sym("IOHIDEventSystemClientCreate", CreateT.self),
              let cs = sym("IOHIDEventSystemClientCopyServices", CopyServicesT.self),
              let cp = sym("IOHIDServiceClientCopyProperty", CopyPropT.self),
              let ce = sym("IOHIDServiceClientCopyEvent", CopyEventT.self),
              let gf = sym("IOHIDEventGetFloatValue", GetFloatT.self) else { return nil }
        create = c; copyServices = cs; copyProperty = cp; copyEvent = ce; getFloat = gf
        client = c(kCFAllocatorDefault)?.takeRetainedValue()
        if client == nil { return nil }
    }

    /// 全部传感器读数：(名称, 摄氏度)
    func readAll() -> [(name: String, celsius: Double)] {
        guard let client, let copyServices, let copyProperty, let copyEvent, let getFloat else { return [] }
        guard let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        var out: [(String, Double)] = []
        for s in services {
            guard let prod = copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String else { continue }
            guard let ev = copyEvent(s, 15 /* temperature */, 0, 0)?.takeRetainedValue() else { continue }
            let t = getFloat(ev, 15 << 16)
            guard t > 1, t < 150 else { continue }
            out.append((prod, t))
        }
        return out
    }

    /// 芯片裸片最高温（排除 NAND / 电池 / 环境温度）
    func hottestSilicon() -> (name: String, celsius: Double)? {
        readAll()
            .filter { r in cpuSensorPrefixes.contains { r.name.hasPrefix($0) } }
            .max { $0.celsius < $1.celsius }
    }

    /// 全传感器最高温（含 NAND 等），兜底用
    func hottestAny() -> (name: String, celsius: Double)? {
        readAll().max { $0.celsius < $1.celsius }
    }
}
