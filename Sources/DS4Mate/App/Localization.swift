import Foundation
import Combine

/// 支持的界面语言。
///
/// 为什么不用 `.lproj` + `Localizable.strings`：
/// 1) 这个 App 用 `scripts/build.sh` 手工组装 bundle，没有 Xcode 工程，加资源目录
///    会让构建脚本多一层拷贝逻辑；
/// 2) 系统级的语言切换必须重启进程才生效（bundle 会缓存 .lproj），而这里要的是
///    「设置里点一下，界面立刻变」。所以改成运行时词典。
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"

    /// 语言自称。选择器里用本语言显示，不做翻译——用户还没读懂目标语言时
    /// 也能认出自己那一项。
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }
}

/// 运行时双语词典。
///
/// 取值顺序：当前语言 → 另一种语言兜底 → 直接回显 key。
/// 兜底而不是回显 key，是为了让「漏翻一条」退化成「看到另一种语言」，
/// 而不是在界面上露出一串 `editor.toolbar.saveAs`。
public final class Localization: ObservableObject {

    public static let shared = Localization()

    /// 语言偏好的持久化 key（与 `AppRuntimeState` 分开存，避免动已有的 Codable 结构）
    public static let userDefaultsKey = "ds4mate.language"
    /// 仅供冒烟测试覆盖：`DS4_LANG=en`
    public static let environmentKey = "DS4_LANG"

    @Published public private(set) var language: AppLanguage

    private init() {
        language = Self.resolveInitialLanguage()
    }

    /// 用户是否已经做过语言选择。
    /// 首次启动（无偏好、也无环境变量覆盖）时返回 false，由启动流程弹选择窗口。
    public var hasChosenLanguage: Bool {
        if ProcessInfo.processInfo.environment[Self.environmentKey] != nil { return true }
        return UserDefaults.standard.string(forKey: Self.userDefaultsKey) != nil
    }

    /// 切换语言。立即生效：所有 `@ObservedObject` 的视图会在下一帧重算。
    public func setLanguage(_ newLanguage: AppLanguage) {
        persist(newLanguage)
        guard newLanguage != language else { return }
        language = newLanguage
    }

    /// 首次选择：只落盘，不发通知以外的副作用。
    public func setLanguageFromFirstRun(_ newLanguage: AppLanguage) {
        setLanguage(newLanguage)
    }

    // MARK: - 取值

    public func t(_ key: String) -> String {
        t(key, in: language)
    }

    /// 取指定语言的值（不看当前语言）。用于「需要知道另一种语言怎么写」的场景，
    /// 例如判断某份预设是不是还没被改过名的初始预设。
    public func t(_ key: String, in language: AppLanguage) -> String {
        switch language {
        case .english:
            return L10nTable.en[key] ?? L10nTable.zh[key] ?? key
        case .chinese:
            return L10nTable.zh[key] ?? L10nTable.en[key] ?? key
        }
    }

    /// 带 `String(format:)` 参数，例如 `t("editor.reset.deleteAll", count)`，
    /// 词条里写 `删除 %d 份预设` / `Delete %d profile(s)`。
    public func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    // MARK: - 解析

    private func persist(_ value: AppLanguage) {
        UserDefaults.standard.set(value.rawValue, forKey: Self.userDefaultsKey)
    }

    /// 环境变量 > 用户偏好 > 系统语言。
    /// 系统语言只作为「还没选过」时的展示默认值，不会写进 UserDefaults——
    /// 否则首次启动的选择窗口就没机会弹出来了。
    public static func resolveInitialLanguage(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppLanguage {
        if let raw = environment[environmentKey], let parsed = parse(raw) {
            return parsed
        }
        if let raw = defaults.string(forKey: userDefaultsKey), let parsed = parse(raw) {
            return parsed
        }
        return systemPreferredLanguage()
    }

    /// 宽松解析：接受 en / en-US / zh / zh-Hans / zh_CN / Chinese 之类写法。
    static func parse(_ raw: String) -> AppLanguage? {
        if let exact = AppLanguage(rawValue: raw) { return exact }
        let normalized = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh") || normalized.hasPrefix("chinese") { return .chinese }
        if normalized.hasPrefix("en") || normalized.hasPrefix("english") { return .english }
        return nil
    }

    static func systemPreferredLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        guard let first = preferredLanguages.first else { return .english }
        return first.lowercased().hasPrefix("zh") ? .chinese : .english
    }
}

// MARK: - 便捷取值

/// 取一条界面文案。视图重算由各视图持有的 `@ObservedObject` 触发。
public func L(_ key: String) -> String {
    Localization.shared.t(key)
}

/// 取一条带参数的界面文案。参数顺序与词条里的 `%@` / `%d` 一致。
public func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localization.shared.t(key), arguments: args)
}
