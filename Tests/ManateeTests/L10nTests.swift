import Testing
import Foundation
@testable import Manatee

/// 语言设置：默认跟随系统、手动切换能持久化、切完 L10n 立刻变。
/// 这几个断言防的是「设置里切了语言但界面没变」这类回调漏接。
@Suite(.serialized)
struct L10nTests {

    @Test func 默认跟随系统() {
        UserDefaults.standard.removeObject(forKey: "ui.language")
        let lang = AppLang(rawValue: UserDefaults.standard.string(forKey: "ui.language") ?? "") ?? .system
        #expect(lang == .system)
    }

    @Test func 三种语言取值合法() {
        #expect(AppLang.allCases.count == 3)
        #expect(AppLang(rawValue: "system") == .system)
        #expect(AppLang(rawValue: "en") == .en)
        #expect(AppLang(rawValue: "zh") == .zh)
        #expect(AppLang(rawValue: "fr") == nil)
    }

    @Test func 切换到英文后L10n返回英文() {
        let store = LangStore.shared
        let original = store.current
        defer { store.current = original }

        store.current = .en
        #expect(store.resolved == "en")
        #expect(L10n.isChinese == false)
        #expect(L10n.t("中文", "English") == "English")

        store.current = .zh
        #expect(store.resolved == "zh")
        #expect(L10n.isChinese == true)
        #expect(L10n.t("中文", "English") == "中文")
    }

    @Test func 切换会写进UserDefaults() {
        let store = LangStore.shared
        let original = store.current
        defer { store.current = original }

        store.current = .zh
        #expect(UserDefaults.standard.string(forKey: "ui.language") == "zh")
        store.current = .en
        #expect(UserDefaults.standard.string(forKey: "ui.language") == "en")
    }
}
