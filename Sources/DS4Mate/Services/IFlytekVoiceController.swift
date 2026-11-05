import Foundation
import AppKit
import ApplicationServices

/// 控制讯飞输入法的语音输入开关。
///
/// 为什么不走快捷键：讯飞 Mac 版（v1.1.1006）的语音热键 UI 标注 ⌃fn，但偏好里
/// `startSpeechingKey` 只存了修饰键（⌘⌥）没有键码，配置残缺导致手按 ⌃fn 也无法触发；
/// 而且它的按键监听走输入法 TSM 事件链，合成事件（CGEvent post / HID 注入）
/// 根本到不了这条链——所有热键路径均不可用（已实测 8 组候选 + 手按 ⌃fn 无效）。
///
/// 唯一实测有效的路径：语音面板是一个常驻窗口（平时停在屏幕外左侧 (-329, 501)），
/// 里面有一枚 AXImage（AXDescription = "voice input start" / "voice input end"）。
/// 面板在屏幕外时 HID 点击无效，所以完整流程是：
///   读原位置 → AX 把窗口移入屏幕 → 重新读按钮坐标 → HID 点击中心 → 移回原位。
public final class IFlytekVoiceController {

    public static let shared = IFlytekVoiceController()

    private let bundleID = "com.iflytek.inputmethod.iFlytekIME"
    /// 面板临时移入屏幕使用的坐标（实测该位置可点击）
    private let onScreenPoint = CGPoint(x: 400, y: 400)

    private init() {}

    /// 讯飞输入法进程是否在运行
    public var isIFlytekRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 切换语音输入状态（开始 ↔ 结束）。返回是否成功点到按钮。
    ///
    /// 面板不存在时（讯飞语音本次启动后还没用过，面板是懒创建的），
    /// 先通过讯飞状态栏菜单的「打开语音输入」把面板召唤出来再点。
    @discardableResult
    public func toggle() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/IFlytek] 讯飞输入法没有运行")
            return false
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 2.0)

        // 面板不存在 = 语音本次启动后还没开过（面板是懒创建的）：
        // 状态栏菜单点「打开语音输入」直接把语音打开，无需再点面板按钮
        if findVoiceButton(in: axApp) == nil {
            NSLog("[DS4Mate/IFlytek] 面板不存在，从状态栏菜单启动语音")
            startVoiceViaStatusMenu()
            Thread.sleep(forTimeInterval: 1.2)
            let ok = findVoiceButton(in: axApp) != nil
            NSLog("[DS4Mate/IFlytek] 菜单启动语音: %@", ok ? "成功" : "失败")
            return ok
        }

        guard let button = findVoiceButton(in: axApp) else { return false }
        let window = button.window

        let originalPosition = window.flatMap { position(of: $0) }
        let originalSize = window.flatMap { size(of: $0) }
        let needsMove: Bool
        if let p = originalPosition, let s = originalSize {
            needsMove = !isFullyOnScreen(CGRect(origin: p, size: s))
        } else {
            needsMove = true
        }

        if needsMove, let window = window {
            set(position: onScreenPoint, of: window)
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 窗口移动后按钮坐标跟着变了，必须重新读
        var ok = false
        if let target = center(of: button.element) {
            ok = click(at: target)
            NSLog("[DS4Mate/IFlytek] click (%.0f, %.0f) -> %@",
                  target.x, target.y, ok ? "sent" : "failed")
        } else {
            NSLog("[DS4Mate/IFlytek] 读不到语音按钮坐标")
        }

        if needsMove {
            Thread.sleep(forTimeInterval: 0.15)
            if let window = window, let original = originalPosition {
                set(position: original, of: window)
            }
        }
        return ok
    }

    // MARK: - 状态栏菜单兜底

    /// 面板懒创建的兜底：点讯飞状态栏图标 → 点菜单第一项「打开语音输入 (⌃fn)」。
    /// NSMenu 不进 AX 树（AXMenu 属性实测拿不到），所以用 CGWindowList 前后对比
    /// 找出新出现的菜单窗口，再按坐标点第一项（第一项固定是打开语音输入）。
    private func startVoiceViaStatusMenu() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXExtrasMenuBarAttribute as CFString, &extrasRef) == .success,
              let extras = extrasRef else { return }
        var itemsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &itemsRef)
        guard let items = itemsRef as? [AXUIElement], let statusItem = items.first else { return }
        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(statusItem, kAXPositionAttribute as CFString, &posRef)
        guard let posValue = posRef else { return }
        var p = CGPoint.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &p)

        let before = windowFrames(ownerPID: Int(app.processIdentifier))
        _ = click(at: CGPoint(x: p.x + 8, y: p.y + 8))
        Thread.sleep(forTimeInterval: 0.6)

        let after = windowFrames(ownerPID: Int(app.processIdentifier))
        let newWindows = after.filter { before[$0.key] == nil }
        guard let menu = newWindows.values.first(where: { $0.width > 150 && $0.height > 50 }) else {
            NSLog("[DS4Mate/IFlytek] 未找到状态栏菜单窗口（新增 %d 个）", newWindows.count)
            return
        }
        Thread.sleep(forTimeInterval: 0.2)
        // 菜单第一项「打开语音输入 (⌃fn)」的中心
        _ = click(at: CGPoint(x: menu.midX, y: menu.minY + 20))
    }

    /// 该进程的全部窗口（窗口号 → frame）
    private func windowFrames(ownerPID pid: Int) -> [UInt32: CGRect] {
        var result: [UInt32: CGRect] = [:]
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return result }
        for window in list where (window[kCGWindowOwnerPID as String] as? Int) == pid {
            guard let number = window[kCGWindowNumber as String] as? UInt32,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double,
                  let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else { continue }
            result[number] = CGRect(x: x, y: y, width: width, height: height)
        }
        return result
    }

    // MARK: - AX 查找

    private struct VoiceButton {
        let element: AXUIElement
        let window: AXUIElement?
    }

    /// 在讯飞进程的 AX 树里找语音按钮（AXImage，AXDescription 以 "voice input" 开头）
    private func findVoiceButton(in app: AXUIElement) -> VoiceButton? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return nil }
        for window in windows {
            if let element = findVoiceButtonDescendant(in: window) {
                return VoiceButton(element: element, window: window)
            }
        }
        return nil
    }

    /// 精确匹配状态按钮（"voice input bg" 是背景图，不能碰）
    private func isStateButton(desc: String) -> Bool {
        desc == "voice input start" || desc == "voice input end"
    }

    private func findVoiceButtonDescendant(in element: AXUIElement) -> AXUIElement? {
        var roleRef: CFTypeRef?
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == "AXImage",
           AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, isStateButton(desc: desc) {
            return element
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let hit = findVoiceButtonDescendant(in: child) { return hit }
        }
        return nil
    }

    // MARK: - 几何与点击

    private func position(of element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    private func size(of element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var s = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &s)
        return s
    }

    private func center(of element: AXUIElement) -> CGPoint? {
        guard let p = position(of: element), let s = size(of: element) else { return nil }
        return CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
    }

    /// 是否完整落在任一屏幕内（讯飞面板平时停在屏幕外左侧）
    private func isFullyOnScreen(_ rect: CGRect) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(rect) }
    }

    private func set(position p: CGPoint, of element: AXUIElement) {
        var point = p
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    /// HID 层鼠标单击（验证过 session 层注入对该面板无效，HID 层有效）
    private func click(at point: CGPoint) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        func post(_ type: CGEventType) {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
            event?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved)
        Thread.sleep(forTimeInterval: 0.05)
        post(.leftMouseDown)
        Thread.sleep(forTimeInterval: 0.05)
        post(.leftMouseUp)
        return true
    }
}
