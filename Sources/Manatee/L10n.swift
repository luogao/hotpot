import Foundation

/// 双语：跟随系统首选语言。文案量小（~40 条），内联在调用点，
/// 不用 .strings 资源 —— 少一层 bundle 本地化配置，改文案时也能一眼看到两种语言。
enum L10n {
    static let isChinese: Bool = {
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.hasPrefix("zh")
    }()

    static func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}
