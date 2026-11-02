import SwiftUI

/// 动作选择器（Sheet）：从分类动作库中选择一个动作。
struct ActionPickerView: View {
    let input: ControllerInput
    let currentAction: Action
    let onSelect: (Action) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var selectedCategory: Action.Category = .mouse

    /// 卡片条目：title 是给人看的名字，action 是要写进绑定的真实动作。
    /// shortcutHint 是卡片下方那行快捷键文本（与 WorkBuddy 快捷键面板保持一致）。
    private struct PickerItem: Hashable {
        let title: String
        let action: Action
        let shortcutHint: String?

        init(_ title: String, _ action: Action, hint: String? = nil) {
            self.title = title
            self.action = action
            self.shortcutHint = hint
        }

        init(_ action: Action) {
            self.title = action.displayName
            self.action = action
            self.shortcutHint = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("为「\(input.displayName)」选择动作")
                    .font(.headline)
                Spacer()
                Button("取消", action: onCancel)
            }
            .padding()

            Divider()

            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索动作…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding()

            HStack(spacing: 0) {
                // 左侧分类
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Action.Category.allCases, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Image(systemName: categoryIcon(category))
                                Text(category.rawValue)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 140)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                Divider()

                // 右侧动作列表
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 12)
                    ], spacing: 12) {
                        ForEach(filteredActions, id: \.self) { item in
                            actionCard(item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - WorkBuddy 快捷键

    /// WorkBuddy 桌面端的真实快捷键，分两部分：
    /// 1) 应用内快捷键（12 条）—— 来自 WorkBuddy「快捷键」面板，窗口聚焦时生效
    /// 2) 菜单栏快捷键（17 条）—— 来自 /Applications/WorkBuddy.app 主进程
    ///    buildApplicationMenu() 的 accelerator，以及 macOS 标准 role
    private static let workBuddyShortcuts: [PickerItem] = [
        // —— 对话与导航（应用内） ——
        PickerItem("全局搜索", .keyPress(keyCode: 40, modifiers: [.maskCommand]), hint: "⌘K"),
        PickerItem("发送消息", .keyPress(keyCode: 36, modifiers: []), hint: "Enter"),
        PickerItem("输入时换行", .keyPress(keyCode: 36, modifiers: [.maskShift]), hint: "⇧ Enter"),
        PickerItem("新建对话", .keyPress(keyCode: 45, modifiers: [.maskCommand]), hint: "⌘N"),
        PickerItem("停止生成", .keyPress(keyCode: 53, modifiers: []), hint: "Esc"),
        PickerItem("上一个任务", .keyPress(keyCode: 33, modifiers: [.maskCommand]), hint: "⌘["),
        PickerItem("下一个任务", .keyPress(keyCode: 30, modifiers: [.maskCommand]), hint: "⌘]"),
        PickerItem("定位当前任务", .keyPress(keyCode: 14, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘E"),
        PickerItem("切换左侧栏", .keyPress(keyCode: 11, modifiers: [.maskCommand]), hint: "⌘B"),
        PickerItem("切换右侧栏", .keyPress(keyCode: 11, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘B"),
        PickerItem("进入/退出全屏", .keyPress(keyCode: 3, modifiers: [.maskCommand, .maskControl]), hint: "⌃⌘F"),
        PickerItem("唤起/隐藏主窗口", .keyPress(keyCode: 13, modifiers: [.maskControl, .maskShift]), hint: "⇧⌃W"),
        // —— 编辑（菜单栏） ——
        PickerItem("撤销", .keyPress(keyCode: 6, modifiers: [.maskCommand]), hint: "⌘Z"),
        PickerItem("重做", .keyPress(keyCode: 6, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘Z"),
        PickerItem("剪切", .keyPress(keyCode: 7, modifiers: [.maskCommand]), hint: "⌘X"),
        PickerItem("复制", .keyPress(keyCode: 8, modifiers: [.maskCommand]), hint: "⌘C"),
        PickerItem("粘贴", .keyPress(keyCode: 9, modifiers: [.maskCommand]), hint: "⌘V"),
        PickerItem("全选", .keyPress(keyCode: 0, modifiers: [.maskCommand]), hint: "⌘A"),
        // —— 窗口（菜单栏） ——
        PickerItem("打开设置", .keyPress(keyCode: 43, modifiers: [.maskCommand]), hint: "⌘,"),
        PickerItem("关闭窗口", .keyPress(keyCode: 13, modifiers: [.maskCommand]), hint: "⌘W"),
        PickerItem("最小化", .keyPress(keyCode: 46, modifiers: [.maskCommand]), hint: "⌘M"),
        PickerItem("隐藏 WorkBuddy", .keyPress(keyCode: 4, modifiers: [.maskCommand]), hint: "⌘H"),
        PickerItem("退出 WorkBuddy", .keyPress(keyCode: 12, modifiers: [.maskCommand]), hint: "⌘Q"),
        // —— 显示（菜单栏） ——
        PickerItem("放大", .keyPress(keyCode: 24, modifiers: [.maskCommand]), hint: "⌘+"),
        PickerItem("缩小", .keyPress(keyCode: 27, modifiers: [.maskCommand]), hint: "⌘-"),
        PickerItem("实际大小", .keyPress(keyCode: 29, modifiers: [.maskCommand]), hint: "⌘0"),
        // —— 调试（菜单栏） ——
        PickerItem("重新加载", .keyPress(keyCode: 15, modifiers: [.maskCommand]), hint: "⌘R"),
        PickerItem("强制重新加载", .keyPress(keyCode: 15, modifiers: [.maskCommand, .maskShift]), hint: "⇧⌘R"),
        PickerItem("开发者工具", .keyPress(keyCode: 34, modifiers: [.maskCommand, .maskAlternate]), hint: "⌥⌘I")
    ]

    // MARK: - Orca 快捷键

    /// Orca.app 内置键绑定（`out/shared/keybindings/definitions*.js`）里挑出来的高频项，
    /// 已按 `~/.orca/keybindings.json` 的个人覆盖修正了 worktree 上/下（⌘↑ / ⌘↓）。
    /// 每条都是普通 `keyPress`，只在 Orca 窗口聚焦时生效。
    private static let orcaShortcuts: [PickerItem] = [
        // —— 全局 / 工作区 ——
        PickerItem("跳转文件", .keyPress(keyCode: 35, modifiers: [.maskCommand]), hint: "⌘P"),
        PickerItem("切换 worktree", .keyPress(keyCode: 38, modifiers: [.maskCommand]), hint: "⌘J"),
        PickerItem("上一个 worktree", .keyPress(keyCode: 126, modifiers: [.maskCommand]), hint: "⌘↑"),
        PickerItem("下一个 worktree", .keyPress(keyCode: 125, modifiers: [.maskCommand]), hint: "⌘↓"),
        PickerItem("新建 worktree", .keyPress(keyCode: 45, modifiers: [.maskCommand]), hint: "⌘N"),
        PickerItem("历史后退", .keyPress(keyCode: 123, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥←"),
        PickerItem("历史前进", .keyPress(keyCode: 124, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥→"),
        PickerItem("左侧栏", .keyPress(keyCode: 11, modifiers: [.maskCommand]), hint: "⌘B"),
        PickerItem("右侧栏", .keyPress(keyCode: 37, modifiers: [.maskCommand]), hint: "⌘L"),
        PickerItem("资源管理器", .keyPress(keyCode: 14, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧E"),
        PickerItem("全局搜索", .keyPress(keyCode: 3, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧F"),
        PickerItem("源码管理", .keyPress(keyCode: 5, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧G"),
        PickerItem("端口面板", .keyPress(keyCode: 34, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧I"),
        PickerItem("浮动终端", .keyPress(keyCode: 0, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥A"),
        PickerItem("语音输入", .keyPress(keyCode: 14, modifiers: [.maskCommand]), hint: "⌘E"),
        PickerItem("插件面板", .keyPress(keyCode: 7, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧X"),
        // —— 标签 ——
        PickerItem("新建终端标签", .keyPress(keyCode: 17, modifiers: [.maskCommand]), hint: "⌘T"),
        PickerItem("新建 agent 标签", .keyPress(keyCode: 17, modifiers: [.maskCommand, .maskAlternate]), hint: "⌘⌥T"),
        PickerItem("新建浏览器标签", .keyPress(keyCode: 11, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧B"),
        PickerItem("新建 Markdown 标签", .keyPress(keyCode: 46, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧M"),
        PickerItem("关闭标签", .keyPress(keyCode: 13, modifiers: [.maskCommand]), hint: "⌘W"),
        PickerItem("恢复关闭的标签", .keyPress(keyCode: 17, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧T"),
        PickerItem("上一个标签", .keyPress(keyCode: 33, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧["),
        PickerItem("下一个标签", .keyPress(keyCode: 30, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧]"),
        PickerItem("重命名标签", .keyPress(keyCode: 15, modifiers: [.maskCommand]), hint: "⌘R"),
        // —— 终端窗格 ——
        PickerItem("终端右分屏", .keyPress(keyCode: 2, modifiers: [.maskCommand]), hint: "⌘D"),
        PickerItem("终端下分屏", .keyPress(keyCode: 2, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧D"),
        PickerItem("清空窗格", .keyPress(keyCode: 40, modifiers: [.maskCommand]), hint: "⌘K"),
        PickerItem("终端搜索", .keyPress(keyCode: 3, modifiers: [.maskCommand]), hint: "⌘F"),
        PickerItem("下一个窗格", .keyPress(keyCode: 30, modifiers: [.maskCommand]), hint: "⌘]"),
        PickerItem("上一个窗格", .keyPress(keyCode: 33, modifiers: [.maskCommand]), hint: "⌘["),
        // —— 编辑器 / 浏览器 ——
        PickerItem("保存文件", .keyPress(keyCode: 1, modifiers: [.maskCommand]), hint: "⌘S"),
        PickerItem("Markdown 预览", .keyPress(keyCode: 9, modifiers: [.maskCommand, .maskShift]), hint: "⌘⇧V"),
        PickerItem("自动换行", .keyPress(keyCode: 6, modifiers: [.maskAlternate]), hint: "⌥Z"),
        PickerItem("浏览器后退", .keyPress(keyCode: 33, modifiers: [.maskCommand]), hint: "⌘["),
        PickerItem("浏览器前进", .keyPress(keyCode: 30, modifiers: [.maskCommand]), hint: "⌘]"),
        PickerItem("重新加载页面", .keyPress(keyCode: 15, modifiers: [.maskCommand]), hint: "⌘R")
    ]

    // MARK: - 分类内容

    private var filteredActions: [PickerItem] {
        let allInCategory: [PickerItem] = {
            switch selectedCategory {
            case .mouse:
                let actions: [Action] = [.mouseLeftClick, .mouseRightClick, .mouseMiddleClick,
                                         .mouseDoubleClick, .mouseDragToggle, .mouseMoveCursor,
                                         .scroll, .fineScroll]
                return actions.map { PickerItem($0) }
            case .keyboard:
                // 30+ 常用键 + 6 个常用组合
                let keys: [Int] = [
                    36,  // Return
                    48,  // Tab
                    49,  // Space
                    51,  // Delete
                    53,  // Escape
                    // 字母（最常用 10 个）
                    12, 13, 14, 15, 17,  // Q W E R T
                    0, 1, 2, 3, 7,        // A S D F X
                    8,                     // C
                    // 方向键
                    123, 124, 125, 126,    // ← → ↓ ↑
                    115, 119,             // Page Up / Page Down
                    // F 区
                    122, 120, 99, 118, 96  // F1-F5
                ]
                let keyActions = keys.map { Action.keyPress(keyCode: $0, modifiers: []) }
                let chords: [Action] = [
                    .keyChord(keyCodes: [8], modifiers: [.maskCommand]),    // ⌘C
                    .keyChord(keyCodes: [9], modifiers: [.maskCommand]),    // ⌘V
                    .keyChord(keyCodes: [7], modifiers: [.maskCommand]),    // ⌘X
                    .keyChord(keyCodes: [0], modifiers: [.maskCommand]),    // ⌘A
                    .keyChord(keyCodes: [15], modifiers: [.maskCommand, .maskShift]), // ⌘⇧R
                    .keyChord(keyCodes: [51], modifiers: [.maskCommand]),   // ⌘Delete
                    .keyChord(keyCodes: [17], modifiers: [.maskAlternate])  // ⌥T（T 的 keyCode 是 17）
                ]
                // 修饰键排最前：按住生效、松开释放，可用于配合鼠标/其他按键
                let modifierActions = ModifierKey.allCases.map { PickerItem(.holdModifier($0)) }
                return modifierActions + (keyActions + chords).map { PickerItem($0) }
            case .workbuddy:
                return Self.workBuddyShortcuts
            case .orca:
                return Self.orcaShortcuts
            case .system:
                return SystemShortcut.allCases.map {
                    PickerItem($0.displayName, .systemShortcut($0), hint: $0.keyCombo)
                }
            case .media:
                return MediaAction.allCases.map { PickerItem($0.displayName, .mediaKey($0)) }
            case .meta:
                let actions: [Action] = [.none, .exitApp, .toggleAppEnabled, .cycleProfile,
                                         .openMainWindow, .toggleQwenVoice, .toggleQwenMic]
                return actions.map { PickerItem($0) }
            }
        }()

        if searchText.isEmpty {
            return allInCategory
        }
        return allInCategory.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.action.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func actionCard(_ item: PickerItem) -> some View {
        Button {
            onSelect(item.action)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: actionIcon(item.action))
                    .imageScale(.large)
                    .frame(height: 22)
                Text(item.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                // WorkBuddy 条目：用快捷键面板里的那套写法（⌘K / ⇧ Enter / Esc）
                if let hint = item.shortcutHint {
                    Text(hint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if item.title != item.action.displayName {
                    Text(item.action.displayName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(8)
            .background(currentAction == item.action
                        ? Color.accentColor.opacity(0.2)
                        : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(currentAction == item.action ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ category: Action.Category) -> String {
        switch category {
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .workbuddy: return "w.circle"
        case .orca: return "o.circle"
        case .system: return "gearshape.2"
        case .media: return "playpause"
        case .meta: return "rectangle.stack"
        }
    }

    private func actionIcon(_ action: Action) -> String {
        switch action {
        case .none: return "circle.slash"
        case .mouseLeftClick: return "computermouse"
        case .mouseRightClick: return "computermouse.fill"
        case .mouseMiddleClick: return "computermouse"
        case .mouseDoubleClick: return "hand.tap"
        case .mouseDragToggle: return "arrow.up.and.down.and.arrow.left.and.right"
        case .mouseMoveCursor: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scroll: return "arrow.up.and.down"
        case .fineScroll: return "arrow.up.and.down.circle"
        case .keyPress: return "keyboard"
        case .keyChord: return "command"
        case .holdModifier(let key):
            switch key {
            case .shift: return "shift"
            case .control: return "control"
            case .option: return "option"
            case .command: return "command"
            case .fn: return "globe"
            }
        case .systemShortcut: return "gearshape.2"
        case .mediaKey: return "playpause"
        case .exitApp: return "power"
        case .toggleAppEnabled: return "switch.2"
        case .cycleProfile: return "rectangle.cycle"
        case .openMainWindow: return "macwindow"
        case .toggleQwenVoice: return "waveform"
        case .toggleQwenMic: return "mic"
        }
    }
}
