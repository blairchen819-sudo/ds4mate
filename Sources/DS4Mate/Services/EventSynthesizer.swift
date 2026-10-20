import Foundation
import CoreGraphics
import AppKit

/// 事件合成器：把 Action 转成 macOS 鼠标/键盘事件。
///
/// 设计原则：
/// - 所有鼠标移动/点击都走 `CGEvent.post(tap: .cgSessionEventTap)`
/// - 键盘事件通过 `kVK_*` 虚拟键码
/// - 修饰键通过 `CGEventFlags`
public final class EventSynthesizer {

    public static let shared = EventSynthesizer()

    private init() {}

    // MARK: - 鼠标移动（持续）

    /// 持续移动鼠标（用于摇杆 → 鼠标移动）
    /// - Parameters:
    ///   - dx: X 增量（像素，正右负左）
    ///   - dy: Y 增量（像素，正下负上）
    public func moveCursor(dx: Double, dy: Double) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let newLocation = CGPoint(
            x: current.x + dx,
            y: current.y + dy
        )
        // 限制在所有屏幕范围内
        let boundedLocation = boundToScreens(newLocation)

        let move = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: boundedLocation,
            mouseButton: .left
        )
        move?.post(tap: .cgSessionEventTap)
    }

    private func boundToScreens(_ point: CGPoint) -> CGPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return point }

        // 简单边界：检查是否在任何屏幕内
        let inAnyScreen = screens.contains { $0.frame.contains(point) }
        if inAnyScreen { return point }

        // 否则夹到主屏幕范围内
        let mainScreen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGPoint(
            x: min(max(point.x, mainScreen.minX), mainScreen.maxX),
            y: min(max(point.y, mainScreen.minY), mainScreen.maxY)
        )
    }

    // MARK: - 鼠标点击

    public func click(type: CGEventType) {
        let down = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero,
            mouseButton: type == .rightMouseDown || type == .rightMouseUp ? .right : .left
        )
        down?.post(tap: .cgSessionEventTap)
        // 50ms 后释放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let upType: CGEventType
            switch type {
            case .leftMouseDown: upType = .leftMouseUp
            case .rightMouseDown: upType = .rightMouseUp
            case .otherMouseDown: upType = .otherMouseUp
            default: return
            }
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: upType,
                mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero,
                mouseButton: type == .rightMouseDown || type == .rightMouseUp ? .right : .left
            )
            up?.post(tap: .cgSessionEventTap)
            _ = self
        }
    }

    public func doubleClick() {
        // 两次快速点击
        click(type: .leftMouseDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.click(type: .leftMouseDown)
        }
    }

    public func middleClick() {
        click(type: .otherMouseDown)
    }

    // MARK: - 滚轮

    /// 滚轮事件（持续）。
    /// - Parameters:
    ///   - dx: 水平滚动量
    ///   - dy: 垂直滚动量
    public func scroll(dx: Int32 = 0, dy: Int32 = 0) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) else { return }
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - 键盘

    public func keyDown(keyCode: Int, modifiers: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        event?.flags = modifiers
        event?.post(tap: .cgSessionEventTap)
    }

    public func keyUp(keyCode: Int, modifiers: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        event?.flags = modifiers
        event?.post(tap: .cgSessionEventTap)
    }

    public func keyPress(keyCode: Int, modifiers: CGEventFlags = []) {
        NSLog("[DS4Mate] EventSynthesizer.keyPress code=\(keyCode) mods=\(modifiers.rawValue)")
        keyDown(keyCode: keyCode, modifiers: modifiers)
        // 50ms 后释放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.keyUp(keyCode: keyCode, modifiers: modifiers)
        }
    }

    public func keyChord(keyCodes: [Int], modifiers: CGEventFlags = []) {
        // 按下所有修饰键
        for code in keyCodes {
            keyDown(keyCode: code, modifiers: modifiers)
        }
        // 释放所有按键
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            for code in keyCodes {
                self?.keyUp(keyCode: code, modifiers: modifiers)
            }
        }
    }

    /// 按住型修饰键：按下置位、松开清除。
    ///
    /// 修饰键不能用 keyDown/keyUp —— 那只是一次敲击，不会改变系统修饰状态。
    /// 必须发 `.flagsChanged` 事件并带上（或清空）对应 flag。
    public func setModifier(_ key: ModifierKey, pressed: Bool) {
        NSLog("[DS4Mate] setModifier \(key.rawValue) pressed=\(pressed)")
        guard let event = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(key.keyCode),
                                  keyDown: pressed) else { return }
        event.type = .flagsChanged
        event.flags = pressed ? key.flag : []
        event.post(tap: .cgSessionEventTap)
    }

    /// 一键清空所有模拟中的修饰键（停用/退出前调用，避免 Shift 卡住）
    public func releaseAllModifiers() {
        for key in ModifierKey.allCases where key.isSoftwareSimulatable {
            setModifier(key, pressed: false)
        }
    }

    // MARK: - 系统快捷键

    public func systemShortcut(_ shortcut: SystemShortcut) {
        // 桌面切换：直接调 SkyLight 的 SLSManagedDisplaySetCurrentSpace。
        // 试过但无效的：CGEvent ⌃←/⌃→（WindowServer 不认合成事件）、
        // CGEvent.postToPid、手势滑动、Mission Control 里点缩略图（坐标不可靠）。
        // 注意必须用 SLS 版，CGS 版只改系统记录、画面不动。
        switch shortcut {
        case .previousDesktop:
            _ = SpaceSwitcher.shared.switchDesktop(-1)
            return
        case .nextDesktop:
            _ = SpaceSwitcher.shared.switchDesktop(1)
            return
        default:
            break
        }

        let (keyCode, modifiers): (Int, CGEventFlags)
        switch shortcut {
        case .previousDesktop: (keyCode, modifiers) = (123, [.maskControl]) // ⌃←（回退路径）
        case .nextDesktop: (keyCode, modifiers) = (124, [.maskControl])     // ⌃→（回退路径）
        case .showDesktop: (keyCode, modifiers) = (103, []) // F11
        // 调度中心 / 应用程序窗口用 ⌃↑ / ⌃↓，比 F3 / F4 可靠：
        // F 区键是否直接生效取决于「将 F1、F2 等键用作标准功能键」这个系统设置
        case .missionControl: (keyCode, modifiers) = (126, [.maskControl]) // ⌃↑
        case .appExpose: (keyCode, modifiers) = (125, [.maskControl])     // ⌃↓
        case .launchpad: (keyCode, modifiers) = (49, [.maskCommand]) // Space
        case .screenshotFull: (keyCode, modifiers) = (20, [.maskCommand, .maskShift]) // 3
        case .screenshotSelection: (keyCode, modifiers) = (21, [.maskCommand, .maskShift]) // 4
        case .lockScreen: (keyCode, modifiers) = (12, [.maskCommand, .maskControl]) // Q
        case .browserBack: (keyCode, modifiers) = (33, [.maskCommand]) // [
        case .browserForward: (keyCode, modifiers) = (30, [.maskCommand]) // ]
        }
        keyChord(keyCodes: [keyCode], modifiers: modifiers)
    }

    // MARK: - 媒体键（v1 走键盘模拟）

    public func mediaKey(_ action: MediaAction) {
        switch action {
        case .playPause, .next, .previous, .volumeUp, .volumeDown, .mute:
            // v1: 通过 NSSound/System Events 触发；简化版用菜单栏播放键
            // macOS 媒体键没有公开 API，v1 走 print + 提示用户用键盘替代
            // 完整实现需走私有 NSEvent，v1.1 候选
            print("[DS4Mate] mediaKey not implemented: \(action)")
        }
    }
}
