import Foundation
import CoreGraphics

/// 某个应用内的一条快捷键语义。
///
/// 为什么需要这张表：`Action.keyPress` 只记录「键码 + 修饰键」，本身不含语义。
/// 同一个组合在不同 app 里含义完全不同——`⌘[` 在 WorkBuddy 是「上一个任务」，
/// 在 Orca 是「上一个窗格」，在浏览器里又是「后退」。要把绑定还原成
/// 「哪个软件里的什么功能」，只能靠一张显式的对照表。
///
/// 同一 app 内也可能有重复：Orca 的 `⌘R` 在编辑器标签上是「重命名标签」，
/// 在浏览器标签上是「重新加载页面」，取决于焦点所在。所以查询接口返回数组。
public struct ShortcutEntry: Hashable, Sendable {
    /// 归属应用名（显示用）
    public let app: String
    /// 该应用里这个键组合的功能名
    public let title: String
    public let action: Action
    /// 与各应用快捷键面板一致的写法（`⌘K` / `⇧ Enter` / `Esc`）
    public let hint: String?

    public init(app: String, title: String, action: Action, hint: String? = nil) {
        self.app = app
        self.title = title
        self.action = action
        self.hint = hint
    }
}

/// 应用内快捷键总表。动作选择器的 WorkBuddy / Orca 分类与编辑器右侧详情面板
/// 共用这一份数据，避免两处各写一遍导致语义漂移。
public enum ShortcutCatalog {

    public static let workBuddyApp = "WorkBuddy"
    public static let orcaApp = "Orca"

    public static var all: [ShortcutEntry] { workBuddy + orca }

    /// 该动作在哪些 app 里已有已知语义。可能命中多条（同 app 内多语境，或跨 app 撞键）。
    public static func matches(for action: Action) -> [ShortcutEntry] {
        all.filter { $0.action == action }
    }

    /// 面板展示用：把同一组合的多条语义压成「app → 功能名列表」。
    /// 顺序按 `all` 中首次出现的顺序，保证 UI 稳定。
    public static func groupedMatches(for action: Action) -> [(app: String, titles: [String])] {
        var order: [String] = []
        var bucket: [String: [String]] = [:]
        for entry in matches(for: action) {
            if bucket[entry.app] == nil {
                order.append(entry.app)
                bucket[entry.app] = []
            }
            // 同 app 内同名的只留一条
            if !(bucket[entry.app]?.contains(entry.title) ?? false) {
                bucket[entry.app]?.append(entry.title)
            }
        }
        return order.map { (app: $0, titles: bucket[$0] ?? []) }
    }

    // MARK: - WorkBuddy

    /// WorkBuddy 桌面端快捷键，分两部分：
    /// 1) 应用内快捷键（12 条）—— 来自 WorkBuddy「快捷键」面板，窗口聚焦时生效
    /// 2) 菜单栏快捷键（17 条）—— 来自 /Applications/WorkBuddy.app 主进程
    ///    buildApplicationMenu() 的 accelerator，以及 macOS 标准 role
    public static let workBuddy: [ShortcutEntry] = [
        // —— 对话与导航（应用内） ——
        ShortcutEntry(app: workBuddyApp, title: "全局搜索", action: .keyPress(keyCode: 40, modifiers: [.maskCommand]), hint: "⌘K"),
        ShortcutEntry(app: workBuddyApp, title: "发送消息", action: .keyPress(keyCode: 36, modifiers: []), hint: "Enter"),
        ShortcutEntry(app: workBuddyApp, title: "输入时换行", action: .keyPress(keyCode: 36, modifiers: [.maskShift]), hint: "⇧ Enter"),
        ShortcutEntry(app: workBuddyApp, title: "新建对话", action: .keyPress(keyCode: 45, modifiers: [.maskCommand]), hint: "⌘N"),
        ShortcutEntry(app: workBuddyApp, title: "停止生成", action: .keyPress(keyCode: 53, modifiers: []), hint: "Esc"),
        ShortcutEntry(app: workBuddyApp, title: "上一个任务", action: .keyPress(keyCode: 33, modifiers: [.maskCommand]), hint: "⌘["),
        ShortcutEntry(app: workBuddyApp, title: "下一个任务", action: .keyPress(keyCode: 30, modifiers: [.maskCommand]), hint: "⌘]"),
        ShortcutEntry(app: workBuddyApp, title: "定位当前任务", action: .keyPress(keyCode: 14, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘E"),
        ShortcutEntry(app: workBuddyApp, title: "切换左侧栏", action: .keyPress(keyCode: 11, modifiers: [.maskCommand]), hint: "⌘B"),
        ShortcutEntry(app: workBuddyApp, title: "切换右侧栏", action: .keyPress(keyCode: 11, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘B"),
        ShortcutEntry(app: workBuddyApp, title: "进入/退出全屏", action: .keyPress(keyCode: 3, modifiers: [.maskCommand, .maskControl]), hint: "⌃⌘F"),
        ShortcutEntry(app: workBuddyApp, title: "唤起/隐藏主窗口", action: .keyPress(keyCode: 13, modifiers: [.maskControl, .maskShift]), hint: "⇧⌃W"),
        // —— 编辑（菜单栏） ——
        ShortcutEntry(app: workBuddyApp, title: "撤销", action: .keyPress(keyCode: 6, modifiers: [.maskCommand]), hint: "⌘Z"),
        ShortcutEntry(app: workBuddyApp, title: "重做", action: .keyPress(keyCode: 6, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘Z"),
        ShortcutEntry(app: workBuddyApp, title: "剪切", action: .keyPress(keyCode: 7, modifiers: [.maskCommand]), hint: "⌘X"),
        ShortcutEntry(app: workBuddyApp, title: "复制", action: .keyPress(keyCode: 8, modifiers: [.maskCommand]), hint: "⌘C"),
        ShortcutEntry(app: workBuddyApp, title: "粘贴", action: .keyPress(keyCode: 9, modifiers: [.maskCommand]), hint: "⌘V"),
        ShortcutEntry(app: workBuddyApp, title: "全选", action: .keyPress(keyCode: 0, modifiers: [.maskCommand]), hint: "⌘A"),
        // —— 窗口（菜单栏） ——
        ShortcutEntry(app: workBuddyApp, title: "打开设置", action: .keyPress(keyCode: 43, modifiers: [.maskCommand]), hint: "⌘,"),
        ShortcutEntry(app: workBuddyApp, title: "关闭窗口", action: .keyPress(keyCode: 13, modifiers: [.maskCommand]), hint: "⌘W"),
        ShortcutEntry(app: workBuddyApp, title: "最小化", action: .keyPress(keyCode: 46, modifiers: [.maskCommand]), hint: "⌘M"),
        ShortcutEntry(app: workBuddyApp, title: "隐藏 WorkBuddy", action: .keyPress(keyCode: 4, modifiers: [.maskCommand]), hint: "⌘H"),
        ShortcutEntry(app: workBuddyApp, title: "退出 WorkBuddy", action: .keyPress(keyCode: 12, modifiers: [.maskCommand]), hint: "⌘Q"),
        // —— 显示（菜单栏） ——
        ShortcutEntry(app: workBuddyApp, title: "放大", action: .keyPress(keyCode: 24, modifiers: [.maskCommand]), hint: "⌘+"),
        ShortcutEntry(app: workBuddyApp, title: "缩小", action: .keyPress(keyCode: 27, modifiers: [.maskCommand]), hint: "⌘-"),
        ShortcutEntry(app: workBuddyApp, title: "实际大小", action: .keyPress(keyCode: 29, modifiers: [.maskCommand]), hint: "⌘0"),
        // —— 调试（菜单栏） ——
        ShortcutEntry(app: workBuddyApp, title: "重新加载", action: .keyPress(keyCode: 15, modifiers: [.maskCommand]), hint: "⌘R"),
        ShortcutEntry(app: workBuddyApp, title: "强制重新加载", action: .keyPress(keyCode: 15, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘R"),
        ShortcutEntry(app: workBuddyApp, title: "开发者工具", action: .keyPress(keyCode: 34, modifiers: [.maskCommand, .maskAlternate]), hint: "⌥⌘I")
    ]

    // MARK: - Orca

    /// Orca.app 内置键绑定（`out/shared/keybindings/definitions*.js`）里挑出来的高频项，
    /// 已按 `~/.orca/keybindings.json` 的个人覆盖修正了 worktree 上/下（⌘↑ / ⌘↓）。
    /// 每条都是普通 `keyPress`，只在 Orca 窗口聚焦时生效。
    public static let orca: [ShortcutEntry] = [
        // —— 全局 / 工作区 ——
        ShortcutEntry(app: orcaApp, title: "跳转文件", action: .keyPress(keyCode: 35, modifiers: [.maskCommand]), hint: "⌘P"),
        ShortcutEntry(app: orcaApp, title: "切换 worktree", action: .keyPress(keyCode: 38, modifiers: [.maskCommand]), hint: "⌘J"),
        ShortcutEntry(app: orcaApp, title: "上一个 worktree", action: .keyPress(keyCode: 126, modifiers: [.maskCommand]), hint: "⌘↑"),
        ShortcutEntry(app: orcaApp, title: "下一个 worktree", action: .keyPress(keyCode: 125, modifiers: [.maskCommand]), hint: "⌘↓"),
        ShortcutEntry(app: orcaApp, title: "新建 worktree", action: .keyPress(keyCode: 45, modifiers: [.maskCommand]), hint: "⌘N"),
        ShortcutEntry(app: orcaApp, title: "历史后退", action: .keyPress(keyCode: 123, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥←"),
        ShortcutEntry(app: orcaApp, title: "历史前进", action: .keyPress(keyCode: 124, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥→"),
        ShortcutEntry(app: orcaApp, title: "左侧栏", action: .keyPress(keyCode: 11, modifiers: [.maskCommand]), hint: "⌘B"),
        ShortcutEntry(app: orcaApp, title: "右侧栏", action: .keyPress(keyCode: 37, modifiers: [.maskCommand]), hint: "⌘L"),
        ShortcutEntry(app: orcaApp, title: "资源管理器", action: .keyPress(keyCode: 14, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧E"),
        ShortcutEntry(app: orcaApp, title: "全局搜索", action: .keyPress(keyCode: 3, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧F"),
        ShortcutEntry(app: orcaApp, title: "源码管理", action: .keyPress(keyCode: 5, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧G"),
        ShortcutEntry(app: orcaApp, title: "端口面板", action: .keyPress(keyCode: 34, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧I"),
        ShortcutEntry(app: orcaApp, title: "浮动终端", action: .keyPress(keyCode: 0, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥A"),
        ShortcutEntry(app: orcaApp, title: "语音输入", action: .keyPress(keyCode: 14, modifiers: [.maskCommand]), hint: "⌘E"),
        ShortcutEntry(app: orcaApp, title: "插件面板", action: .keyPress(keyCode: 7, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧X"),
        // —— 标签 ——
        ShortcutEntry(app: orcaApp, title: "新建终端标签", action: .keyPress(keyCode: 17, modifiers: [.maskCommand]), hint: "⌘T"),
        ShortcutEntry(app: orcaApp, title: "新建 agent 标签", action: .keyPress(keyCode: 17, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥T"),
        ShortcutEntry(app: orcaApp, title: "新建浏览器标签", action: .keyPress(keyCode: 11, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧B"),
        ShortcutEntry(app: orcaApp, title: "新建 Markdown 标签", action: .keyPress(keyCode: 46, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧M"),
        ShortcutEntry(app: orcaApp, title: "关闭标签", action: .keyPress(keyCode: 13, modifiers: [.maskCommand]), hint: "⌘W"),
        ShortcutEntry(app: orcaApp, title: "恢复关闭的标签", action: .keyPress(keyCode: 17, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧T"),
        ShortcutEntry(app: orcaApp, title: "上一个标签", action: .keyPress(keyCode: 33, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧["),
        ShortcutEntry(app: orcaApp, title: "下一个标签", action: .keyPress(keyCode: 30, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧]"),
        ShortcutEntry(app: orcaApp, title: "重命名标签", action: .keyPress(keyCode: 15, modifiers: [.maskCommand]), hint: "⌘R"),
        // —— 终端窗格 ——
        ShortcutEntry(app: orcaApp, title: "终端右分屏", action: .keyPress(keyCode: 2, modifiers: [.maskCommand]), hint: "⌘D"),
        ShortcutEntry(app: orcaApp, title: "终端下分屏", action: .keyPress(keyCode: 2, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧D"),
        ShortcutEntry(app: orcaApp, title: "清空窗格", action: .keyPress(keyCode: 40, modifiers: [.maskCommand]), hint: "⌘K"),
        ShortcutEntry(app: orcaApp, title: "终端搜索", action: .keyPress(keyCode: 3, modifiers: [.maskCommand]), hint: "⌘F"),
        ShortcutEntry(app: orcaApp, title: "下一个窗格", action: .keyPress(keyCode: 30, modifiers: [.maskCommand]), hint: "⌘]"),
        ShortcutEntry(app: orcaApp, title: "上一个窗格", action: .keyPress(keyCode: 33, modifiers: [.maskCommand]), hint: "⌘["),
        // —— 编辑器 / 浏览器 ——
        ShortcutEntry(app: orcaApp, title: "保存文件", action: .keyPress(keyCode: 1, modifiers: [.maskCommand]), hint: "⌘S"),
        ShortcutEntry(app: orcaApp, title: "Markdown 预览", action: .keyPress(keyCode: 9, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧V"),
        ShortcutEntry(app: orcaApp, title: "自动换行", action: .keyPress(keyCode: 6, modifiers: [.maskAlternate]), hint: "⌥Z"),
        ShortcutEntry(app: orcaApp, title: "浏览器后退", action: .keyPress(keyCode: 33, modifiers: [.maskCommand]), hint: "⌘["),
        ShortcutEntry(app: orcaApp, title: "浏览器前进", action: .keyPress(keyCode: 30, modifiers: [.maskCommand]), hint: "⌘]"),
        ShortcutEntry(app: orcaApp, title: "重新加载页面", action: .keyPress(keyCode: 15, modifiers: [.maskCommand]), hint: "⌘R")
    ]
}
