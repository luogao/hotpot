import Foundation
import Combine

/// 界面语言。`system` 跟随系统首选语言，其余是用户手动覆盖（设置 → 通用 → 语言）。
enum AppLang: String, CaseIterable, Identifiable {
    case system, en, zh
    var id: String { rawValue }

    /// picker 上显示的名字，用各自语言写，不翻译
    var label: String {
        switch self {
        case .system: return L10n.t("跟随系统", "System")
        case .en:     return "English"
        case .zh:     return "简体中文"
        }
    }

    /// 窄胶囊里用的短标签
    var shortLabel: String {
        switch self {
        case .system: return L10n.t("自动", "Auto")
        case .en:     return "EN"
        case .zh:     return "中"
        }
    }
}

/// 当前语言的单一来源。改语言会发 `objectWillChange`，
/// 视图 `@ObservedObject var lang = LangStore.shared` 就能整体重绘。
final class LangStore: ObservableObject {
    static let shared = LangStore()
    private static let key = "ui.language"

    @Published var current: AppLang {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
            resolved = Self.resolve(current)
        }
    }

    /// 实际生效的语言：`en` 或 `zh`
    private(set) var resolved: String

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? AppLang.system.rawValue
        let lang = AppLang(rawValue: saved) ?? .system
        current = lang
        resolved = Self.resolve(lang)
    }

    private static func resolve(_ lang: AppLang) -> String {
        switch lang {
        case .en: return "en"
        case .zh: return "zh"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh" : "en"
        }
    }
}

/// 双语：跟随系统首选语言，也可在设置里手动切换。
/// 文案内联在调用点，改的时候两种语言一眼都看得到。
enum L10n {
    static var isChinese: Bool { LangStore.shared.resolved == "zh" }

    static func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}
