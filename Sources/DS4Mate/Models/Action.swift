import Foundation
import CoreGraphics

/// macOS 系统快捷键预设。
public enum SystemShortcut: String, Codable, CaseIterable, Hashable, Sendable {
    case previousDesktop      // ⌃← 向左一个桌面（Spaces）
    case nextDesktop          // ⌃→ 向右一个桌面
    case showDesktop        // F11
    case missionControl     // F3
    case appExpose          // Ctrl+F4
    case launchpad          // Cmd+Space
    case screenshotFull     // Cmd+Shift+3
    case screenshotSelection // Cmd+Shift+4
    case lockScreen         // Cmd+Ctrl+Q
    case browserBack        // Cmd+[
    case browserForward     // Cmd+]

    public var displayName: String {
        switch self {
        case .previousDesktop: return "上一个桌面"
        case .nextDesktop: return "下一个桌面"
        case .showDesktop: return "显示桌面"
        case .missionControl: return "调度中心"
        case .appExpose: return "App Exposé"
        case .launchpad: return "Launchpad"
        case .screenshotFull: return "全屏截图"
        case .screenshotSelection: return "区域截图"
        case .lockScreen: return "锁屏"
        case .browserBack: return "浏览器后退"
        case .browserForward: return "浏览器前进"
        }
    }

    public var keyCombo: String {
        switch self {
        case .previousDesktop: return "⌃←"
        case .nextDesktop: return "⌃→"
        case .showDesktop: return "F11"
        case .missionControl: return "F3"
        case .appExpose: return "⌃F4"
        case .launchpad: return "⌘Space"
        case .screenshotFull: return "⌘⇧3"
        case .screenshotSelection: return "⌘⇧4"
        case .lockScreen: return "⌘⌃Q"
        case .browserBack: return "⌘["
        case .browserForward: return "⌘]"
        }
    }
}

/// 媒体键（v1 不通过 NSEvent 触发，改用键盘模拟）
public enum MediaAction: String, Codable, CaseIterable, Hashable, Sendable {
    case playPause
    case next
    case previous
    case volumeUp
    case volumeDown
    case mute

    public var displayName: String {
        switch self {
        case .playPause: return "播放 / 暂停"
        case .next: return "下一曲"
        case .previous: return "上一曲"
        case .volumeUp: return "音量增大"
        case .volumeDown: return "音量减小"
        case .mute: return "静音"
        }
    }
}

/// 可"按住"的修饰键。
///
/// 与 `Action.keyPress` 的区别：普通按键按下就抬起（50ms 内完成一次敲击），
/// 而修饰键必须「手柄按住时保持激活，松开时才释放」，否则无法实现
/// 「按住 Shift 点鼠标选文字」「按住 Control 点鼠标右键」这类操作。
public enum ModifierKey: String, Codable, CaseIterable, Hashable, Sendable {
    case shift
    case control
    case option
    case fn
    case command

    public var displayName: String {
        switch self {
        case .shift: return "Shift ⇧"
        case .control: return "Control ⌃"
        case .option: return "Option ⌥"
        case .fn: return "Fn"
        case .command: return "Command ⌘"
        }
    }

    /// 左手键位（Carbon kVK_*）
    public var keyCode: Int {
        switch self {
        case .shift: return 56
        case .control: return 59
        case .option: return 58
        case .fn: return 63
        case .command: return 55
        }
    }

    public var flag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .fn: return .maskSecondaryFn
        case .command: return .maskCommand
        }
    }

    /// 五个修饰键均已实测：post `.flagsChanged` 后
    /// `CGEventSource.flagsState(.combinedSessionState)` 能读到对应 bit，释放后清除。
    /// Fn 的 bit（maskSecondaryFn）同样能置位，但系统级行为取决于应用是否识别。
    public var isSoftwareSimulatable: Bool { true }
}

/// 动作：按键 → 鼠标/键盘/系统命令 的目标动作。
///
/// 设计原则：
/// - 编码为 `{"type": "mouseLeftClick"}` 或 `{"type": "keyPress", "keyCode": 36}`
/// - Codable + Hashable 便于持久化和 SwiftUI 列表去重
public enum Action: Codable, Hashable, Sendable {

    // MARK: - 键码 → 人类可读名

    /// Carbon kVK 编码 → 用户看得懂的键名（用于 UI 显示）
    public static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        // 字母
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        // 数字
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        // 符号
        case 24: return "="  // =
        case 27: return "-"
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 42: return "\\"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"
        // 特殊
        case 36: return "Return ↩"
        case 48: return "Tab ⇥"
        case 49: return "Space ␣"
        case 51: return "Delete ⌫"
        case 53: return "Escape ⎋"
        case 54: return "Right Cmd ⌘"
        case 55: return "Left Cmd ⌘"
        case 56: return "Left Shift ⇧"
        case 57: return "Caps Lock ⇪"
        case 58: return "Left Option ⌥"
        case 59: return "Left Control ⌃"
        case 60: return "Right Shift ⇧"
        case 61: return "Right Option ⌥"
        case 62: return "Right Control ⌃"
        case 63: return "Fn"
        // F 区
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // 方向键
        case 123: return "← Left"
        case 124: return "→ Right"
        case 125: return "↓ Down"
        case 126: return "↑ Up"
        // 翻页
        case 115: return "Home ↖"
        case 116: return "Page Up ⇞"
        case 119: return "End ↘"
        case 121: return "Page Down ⇟"
        default: return "键码 \(keyCode)"
        }
    }

    /// 修饰键的可读组合（"⌘⇧4" 形式）
    public static func modifierString(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        return parts.joined()
    }

    case none                       // 禁用该按键
    case mouseLeftClick
    case mouseRightClick
    case mouseMiddleClick
    case mouseDoubleClick
    case mouseDragToggle
    case mouseMoveCursor            // 摇杆 → 鼠标移动（持续）
    case scroll                     // 摇杆 → 滚轮（持续）
    case fineScroll                 // 扳机 → 精细滚轮（持续）
    case keyPress(keyCode: Int, modifiers: CGEventFlags)
    case keyChord(keyCodes: [Int], modifiers: CGEventFlags)
    /// 按住型修饰键：手柄按下时置位，松开时清除
    case holdModifier(ModifierKey)
    case systemShortcut(SystemShortcut)
    case mediaKey(MediaAction)
    case exitApp
    case toggleAppEnabled
    case cycleProfile
    case openMainWindow
    /// 切换千问客户端的语音通话开关（走辅助功能接口点它的通话按钮）
    case toggleQwenVoice
    /// 切换千问客户端的麦克风（聊天窗口常开，只控制麦克风）
    case toggleQwenMic

    public var displayName: String {
        switch self {
        case .none: return "禁用"
        case .mouseLeftClick: return "鼠标左键"
        case .mouseRightClick: return "鼠标右键"
        case .mouseMiddleClick: return "鼠标中键"
        case .mouseDoubleClick: return "鼠标双击"
        case .mouseDragToggle: return "切换拖拽模式"
        case .mouseMoveCursor: return "鼠标移动（持续）"
        case .scroll: return "滚轮（持续）"
        case .fineScroll: return "精细滚轮"
        case .keyPress(let code, let mods):
            let m = Self.modifierString(mods)
            return m.isEmpty ? Self.keyName(for: code) : "\(m)\(Self.keyName(for: code))"
        case .keyChord(let codes, let mods):
            let m = Self.modifierString(mods)
            let keys = codes.map { Self.keyName(for: $0) }.joined(separator: "+")
            return m.isEmpty ? keys : "\(m)\(keys)"
        case .holdModifier(let key):
            return "按住 \(key.displayName)"
        case .systemShortcut(let s): return s.displayName
        case .mediaKey(let m): return m.displayName
        case .exitApp: return "退出 DS4Mate"
        case .toggleAppEnabled: return "切换总开关"
        case .cycleProfile: return "循环切换预设"
        case .openMainWindow: return "打开主窗口"
        case .toggleQwenVoice: return "切换千问语音"
        case .toggleQwenMic: return "切换千问麦克风"
        }
    }

    /// 一句话说明这个动作**实际会做什么**（右侧详情面板用）。
    /// `displayName` 只是简短标签（"⌘⇧4"），用户看不出它会触发什么，这里补上语义。
    public var functionDescription: String {
        switch self {
        case .none:
            return "该键被禁用，按下不会有任何反应"
        case .mouseLeftClick:
            return "模拟一次鼠标左键单击（按下 + 抬起）"
        case .mouseRightClick:
            return "模拟一次鼠标右键单击，弹出右键菜单"
        case .mouseMiddleClick:
            return "模拟一次鼠标中键单击"
        case .mouseDoubleClick:
            return "模拟一次鼠标左键双击"
        case .mouseDragToggle:
            return "按一次按住左键进入拖拽，再按一次松开"
        case .mouseMoveCursor:
            return "按住期间按摇杆方向持续移动鼠标指针"
        case .scroll:
            return "按住期间按摇杆方向持续滚动"
        case .fineScroll:
            return "扳机行程越深滚动越快（精细档位）"
        case .keyPress(let code, let modifiers):
            let combo = Self.modifierString(modifiers)
            let key = Self.keyName(for: code)
            return combo.isEmpty ? "敲击一次 \(key)" : "发送快捷键 \(combo)\(key)"
        case .keyChord(let codes, let modifiers):
            let combo = Self.modifierString(modifiers)
            let keys = codes.map { Self.keyName(for: $0) }.joined(separator: " + ")
            return combo.isEmpty
                ? "依次敲击 \(keys)"
                : "按住 \(combo) 并依次敲击 \(keys)"
        case .holdModifier(let key):
            return "手柄按住期间保持 \(key.displayName) 按下，松开即释放，可与其他动作组合"
        case .systemShortcut(let shortcut):
            return "触发系统快捷键 \(shortcut.keyCombo) —— \(shortcut.displayName)"
        case .mediaKey(let media):
            return "媒体控制：\(media.displayName)"
        case .exitApp:
            return "退出 DS4Mate，手柄映射随之停止"
        case .toggleAppEnabled:
            return "临时开关手柄映射，不退出应用"
        case .cycleProfile:
            return "切换到下一套预设，与设置里的全局切换键等效"
        case .openMainWindow:
            return "弹出键位编辑器主窗口"
        case .toggleQwenVoice:
            return "通过辅助功能接口点击千问客户端的语音通话按钮"
        case .toggleQwenMic:
            return "通过辅助功能接口点击千问客户端的麦克风按钮"
        }
    }

    // MARK: - Hashable（手动实现以避免 CGEventFlags 不符合 Hashable）

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .none: hasher.combine(0)
        case .mouseLeftClick: hasher.combine(1)
        case .mouseRightClick: hasher.combine(2)
        case .mouseMiddleClick: hasher.combine(3)
        case .mouseDoubleClick: hasher.combine(4)
        case .mouseDragToggle: hasher.combine(5)
        case .mouseMoveCursor: hasher.combine(6)
        case .scroll: hasher.combine(7)
        case .fineScroll: hasher.combine(8)
        case .keyPress(let code, let mods):
            hasher.combine(9)
            hasher.combine(code)
            hasher.combine(mods.rawValue)
        case .keyChord(let codes, let mods):
            hasher.combine(10)
            hasher.combine(codes)
            hasher.combine(mods.rawValue)
        case .systemShortcut(let s):
            hasher.combine(11)
            hasher.combine(s)
        case .mediaKey(let m):
            hasher.combine(12)
            hasher.combine(m)
        case .exitApp: hasher.combine(13)
        case .toggleAppEnabled: hasher.combine(14)
        case .cycleProfile: hasher.combine(15)
        case .holdModifier(let m):
            hasher.combine(17)
            hasher.combine(m)
        case .openMainWindow: hasher.combine(16)
        case .toggleQwenVoice: hasher.combine(18)
        case .toggleQwenMic: hasher.combine(19)
        }
    }

    public static func == (lhs: Action, rhs: Action) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.mouseLeftClick, .mouseLeftClick): return true
        case (.mouseRightClick, .mouseRightClick): return true
        case (.mouseMiddleClick, .mouseMiddleClick): return true
        case (.mouseDoubleClick, .mouseDoubleClick): return true
        case (.mouseDragToggle, .mouseDragToggle): return true
        case (.mouseMoveCursor, .mouseMoveCursor): return true
        case (.scroll, .scroll): return true
        case (.fineScroll, .fineScroll): return true
        case (.keyPress(let c1, let m1), .keyPress(let c2, let m2)):
            return c1 == c2 && m1 == m2
        case (.keyChord(let c1, let m1), .keyChord(let c2, let m2)):
            return c1 == c2 && m1 == m2
        case (.holdModifier(let a), .holdModifier(let b)):
            return a == b
        case (.systemShortcut(let s1), .systemShortcut(let s2)):
            return s1 == s2
        case (.mediaKey(let m1), .mediaKey(let m2)):
            return m1 == m2
        case (.exitApp, .exitApp): return true
        case (.toggleAppEnabled, .toggleAppEnabled): return true
        case (.cycleProfile, .cycleProfile): return true
        case (.openMainWindow, .openMainWindow): return true
        case (.toggleQwenVoice, .toggleQwenVoice): return true
        case (.toggleQwenMic, .toggleQwenMic): return true
        default: return false
        }
    }

    /// 动作分类（用于动作选择器的左侧分类）
    public enum Category: String, CaseIterable, Hashable {
        case mouse = "鼠标"
        case keyboard = "键盘"
        case workbuddy = "WorkBuddy"
        case orca = "Orca"
        case system = "系统"
        case media = "媒体"
        case meta = "元动作"

        /// 分类对应的 SF Symbol（选择器侧栏与详情面板共用）
        public var iconName: String {
            switch self {
            case .mouse: return "computermouse"
            case .keyboard: return "keyboard"
            case .workbuddy: return "w.circle"
            case .orca: return "o.circle"
            case .system: return "gearshape.2"
            case .media: return "playpause"
            case .meta: return "rectangle.stack"
            }
        }
    }

    public var category: Category {
        switch self {
        case .none: return .meta
        case .mouseLeftClick, .mouseRightClick, .mouseMiddleClick,
             .mouseDoubleClick, .mouseDragToggle, .mouseMoveCursor,
             .scroll, .fineScroll:
            return .mouse
        case .keyPress, .keyChord, .holdModifier:
            return .keyboard
        case .systemShortcut:
            return .system
        case .mediaKey:
            return .media
        case .exitApp, .toggleAppEnabled, .cycleProfile, .openMainWindow, .toggleQwenVoice, .toggleQwenMic:
            return .meta
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case keyCode
        case keyCodes
        case modifiers
        case modifierKey
        case systemShortcut
        case mediaAction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "none": self = .none
        case "mouseLeftClick": self = .mouseLeftClick
        case "mouseRightClick": self = .mouseRightClick
        case "mouseMiddleClick": self = .mouseMiddleClick
        case "mouseDoubleClick": self = .mouseDoubleClick
        case "mouseDragToggle": self = .mouseDragToggle
        case "mouseMoveCursor": self = .mouseMoveCursor
        case "scroll": self = .scroll
        case "fineScroll": self = .fineScroll
        case "keyPress":
            let code = try c.decode(Int.self, forKey: .keyCode)
            let rawMods = try c.decode(UInt64.self, forKey: .modifiers)
            self = .keyPress(keyCode: code, modifiers: CGEventFlags(rawValue: rawMods))
        case "keyChord":
            let codes = try c.decode([Int].self, forKey: .keyCodes)
            let rawMods = try c.decode(UInt64.self, forKey: .modifiers)
            self = .keyChord(keyCodes: codes, modifiers: CGEventFlags(rawValue: rawMods))
        case "holdModifier":
            let m = try c.decode(ModifierKey.self, forKey: .modifierKey)
            self = .holdModifier(m)
        case "systemShortcut":
            let s = try c.decode(SystemShortcut.self, forKey: .systemShortcut)
            self = .systemShortcut(s)
        case "mediaKey":
            let m = try c.decode(MediaAction.self, forKey: .mediaAction)
            self = .mediaKey(m)
        case "exitApp": self = .exitApp
        case "toggleAppEnabled": self = .toggleAppEnabled
        case "cycleProfile": self = .cycleProfile
        case "openMainWindow": self = .openMainWindow
        case "toggleQwenVoice": self = .toggleQwenVoice
        case "toggleQwenMic": self = .toggleQwenMic
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown Action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode("none", forKey: .type)
        case .mouseLeftClick: try c.encode("mouseLeftClick", forKey: .type)
        case .mouseRightClick: try c.encode("mouseRightClick", forKey: .type)
        case .mouseMiddleClick: try c.encode("mouseMiddleClick", forKey: .type)
        case .mouseDoubleClick: try c.encode("mouseDoubleClick", forKey: .type)
        case .mouseDragToggle: try c.encode("mouseDragToggle", forKey: .type)
        case .mouseMoveCursor: try c.encode("mouseMoveCursor", forKey: .type)
        case .scroll: try c.encode("scroll", forKey: .type)
        case .fineScroll: try c.encode("fineScroll", forKey: .type)
        case .keyPress(let code, let mods):
            try c.encode("keyPress", forKey: .type)
            try c.encode(code, forKey: .keyCode)
            try c.encode(mods.rawValue, forKey: .modifiers)
        case .keyChord(let codes, let mods):
            try c.encode("keyChord", forKey: .type)
            try c.encode(codes, forKey: .keyCodes)
            try c.encode(mods.rawValue, forKey: .modifiers)
        case .holdModifier(let m):
            try c.encode("holdModifier", forKey: .type)
            try c.encode(m, forKey: .modifierKey)
        case .systemShortcut(let s):
            try c.encode("systemShortcut", forKey: .type)
            try c.encode(s, forKey: .systemShortcut)
        case .mediaKey(let m):
            try c.encode("mediaKey", forKey: .type)
            try c.encode(m, forKey: .mediaAction)
        case .exitApp: try c.encode("exitApp", forKey: .type)
        case .toggleAppEnabled: try c.encode("toggleAppEnabled", forKey: .type)
        case .cycleProfile: try c.encode("cycleProfile", forKey: .type)
        case .openMainWindow: try c.encode("openMainWindow", forKey: .type)
        case .toggleQwenVoice: try c.encode("toggleQwenVoice", forKey: .type)
        case .toggleQwenMic: try c.encode("toggleQwenMic", forKey: .type)
        }
    }
}
