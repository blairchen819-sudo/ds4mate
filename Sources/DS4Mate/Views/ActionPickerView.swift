import SwiftUI

/// 动作选择器（Sheet）：从分类动作库中选择一个动作。
struct ActionPickerView: View {
    let input: ControllerInput
    let currentAction: Action
    let onSelect: (Action) -> Void
    let onCancel: () -> Void

    @ObservedObject private var i18n = Localization.shared
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
                Text(i18n.t("picker.title", input.displayName))
                    .font(.headline)
                Spacer()
                Button(i18n.t("common.cancel"), action: onCancel)
            }
            .padding()

            Divider()

            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(i18n.t("picker.search"), text: $searchText)
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
                                Image(systemName: category.iconName)
                                Text(category.displayName)
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

    // MARK: - 应用内快捷键

    /// 数据源统一在 `ShortcutCatalog`（Models/ShortcutCatalog.swift），这里只做展示层映射。
    /// 编辑器右侧详情面板用的是同一份表，所以能把「⌘P」还原成「Orca · 跳转文件」。
    private static let workBuddyShortcuts: [PickerItem] =
        ShortcutCatalog.workBuddy.map { PickerItem($0.title, $0.action, hint: $0.hint) }

    private static let orcaShortcuts: [PickerItem] =
        ShortcutCatalog.orca.map { PickerItem($0.title, $0.action, hint: $0.hint) }

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
                                         .openMainWindow, .toggleQwenVoice, .toggleQwenMic,
                                         .iflytekVoice]
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
        case .iflytekVoice: return "mic.badge.waveform"
        }
    }
}
