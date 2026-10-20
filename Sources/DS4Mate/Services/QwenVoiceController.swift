import Foundation
import AppKit
import ApplicationServices

/// 控制千问（Qwen）客户端的语音通话开关。
///
/// 千问没有注册任何全局快捷键（已解包 `qwen-voice-agent.asar` 和 `qwen-light-apps.asar`，
/// 只有内部 IPC `toggleVoiceAgentFromShortcut`，没有 accelerator），
/// 语音只能靠界面底部那个圆形通话按钮开关。
///
/// 所以走辅助功能（AX）接口：找到那个按钮，直接执行 AXPress。
public final class QwenVoiceController {

    public static let shared = QwenVoiceController()

    private let bundleID = "com.alibaba.tongyi"

    private init() {}

    /// 千问是否在运行
    public var isQwenRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 切换千问语音通话状态。返回是否成功点到按钮。
    ///
    /// 两个平台限制：
    /// 1. 开启语音时必须让千问窗口 active，否则 Chromium 忽略后台窗口按钮的 AXPress。
    /// 2. **跨 Space 时 AX 树本身就不完整**（实测只剩侧边栏，170 多个节点，聊天区按钮不在里面），
    ///    所以「找不到按钮」时也要先切过去再找一次。
    @discardableResult
    public func toggleVoice() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Qwen] 千问没有运行")
            return false
        }

        let previous = NSWorkspace.shared.frontmostApplication
        let originalSpace = SpaceSwitcher.shared.currentSpaceID
        let isFrontmost = previous?.bundleIdentifier == bundleID

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 2.0)

        if let best = bestButton(in: axApp) {
            let isOpening = best.text.contains("语音聊天") || best.text.contains("语音通话")
            if isOpening && !isFrontmost {
                NSLog("[DS4Mate/Qwen] 开启需激活（原前台：%@，空间 %@）",
                      previous?.localizedName ?? "?",
                      originalSpace.map { "\($0)" } ?? "?")
                activateAndPress(app, originalSpace: originalSpace, previous: previous)
                return true
            }
            let r = AXUIElementPerformAction(best.element, kAXPressAction as CFString)
            NSLog("[DS4Mate/Qwen] press \"%@\" -> %d", best.text, Int(r.rawValue))
            return r == .success
        }

        // 找不到按钮：大概率在别的 Space，AX 树不完整
        NSLog("[DS4Mate/Qwen] 找不到按钮（前台：%@，空间 %@），先激活再找",
              previous?.localizedName ?? "?",
              originalSpace.map { "\($0)" } ?? "?")
        activateAndPress(app, originalSpace: originalSpace, previous: previous)
        return true
    }

    /// 切到千问所在桌面 → 找按钮并点击 → 切回原桌面与原应用
    private func activateAndPress(_ app: NSRunningApplication,
                                  originalSpace: UInt64?,
                                  previous: NSRunningApplication?) {
        // open 走 LaunchServices，能真正跨 Space 把窗口带过来；activate() 不行
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "/Applications/Qianwen.app"]
        do {
            try task.run()
        } catch {
            NSLog("[DS4Mate/Qwen] open 失败: %@", error.localizedDescription)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 2.0)

            if let btn = self.bestButton(in: ax) {
                let r = AXUIElementPerformAction(btn.element, kAXPressAction as CFString)
                NSLog("[DS4Mate/Qwen] press \"%@\" -> %d", btn.text, Int(r.rawValue))
            } else {
                NSLog("[DS4Mate/Qwen] 激活后仍找不到按钮（可能在文档界面）")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let space = originalSpace {
                    SpaceSwitcher.shared.switchToSpace(space)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    previous?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
            }
        }
    }

    /// 调试：切到千问后导出界面上所有带文本的 AX 元素
    public func dumpAllButtons() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleID).first else {
                NSLog("[DS4Mate/Qwen] dump: 千问未运行")
                return
            }

            // 先切到千问，跨 Space / 后台时 AX 树不完整
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "/Applications/Qianwen.app"]
            try? task.run()
            Thread.sleep(forTimeInterval: 1.5)

            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 3.0)
            var visited = 0
            self.dumpButtonTree(ax, depth: 0, visited: &visited)
            NSLog("[DS4Mate/Qwen] dump 结束，访问 %d 节点", visited)
        }
    }

    private func dumpButtonTree(_ element: AXUIElement, depth: Int, visited: inout Int) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? "?"
        // 只关心可点击元素及窗口，带上屏幕坐标便于定位无文本的图标按钮
        if role == "AXButton" || role == "AXLink" || role == "AXPopUpButton" ||
           role == "AXWindow" || role == "AXTextArea" || role == "AXTextField" {
            let parts = strings(element)
            NSLog("[DS4Mate/Qwen] %@ %@ [%@]", role, frameString(element), parts.joined(separator: " | "))
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { dumpButtonTree(c, depth: depth + 1, visited: &visited) }
    }

    private func frameString(_ element: AXUIElement) -> String {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var p = CGPoint.zero
        var s = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        return String(format: "(%.0f,%.0f %.0fx%.0f)", p.x, p.y, s.width, s.height)
    }

    /// 切换千问的麦克风开关。
    ///
    /// 实测结论（四条路全试过）：
    /// - 全局鼠标点击 ✅ 唯一有效的
    /// - `CGEvent.postToPid` ❌
    /// - `AXPress`（元素带 AXPress 也）❌ 返回 success 但不触发
    /// - SkyLight `SLEventPostToPid` ❌
    /// 千问是 Chromium，合成事件一律忽略，只认真正的全局鼠标。
    /// 所以**跨桌面时只能先把窗口切过来、点一下、再切回去**。
    ///
    /// 另一条硬规则：语音会话没开时**什么都不做**。
    /// 否则会去点麦克风图标，等于帮用户开了语音，这不是他要的。
    @discardableResult
    public func toggleMicrophone() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Qwen] 千问没有运行")
            return false
        }

        let previous = NSWorkspace.shared.frontmostApplication
        let wasFrontmost = previous?.bundleIdentifier == bundleID
        let onScreen = isQwenWindowOnScreen()

        if wasFrontmost && onScreen {
            return clickMicIfSessionActive(app)
        }

        // 跨桌面 / 后台：open -a 会切到千问所在的 Space，切完再切回来
        NSLog("[DS4Mate/Qwen] 千问不在当前桌面，先切过去（原前台：%@）", previous?.localizedName ?? "?")
        bringQwenToFront { ready in
            if ready {
                _ = self.clickMicIfSessionActive(app)
            } else {
                NSLog("[DS4Mate/Qwen] 等不到千问窗口，放弃")
            }
            // 留一点时间让点击生效，再切回原来的应用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.restoreFocus(to: previous)
            }
        }
        return true
    }

    /// 会话开着才动麦克风；没开就什么都不做
    @discardableResult
    private func clickMicIfSessionActive(_ app: NSRunningApplication) -> Bool {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 2.5)

        if let notice = voiceSessionNotice(in: ax) {
            NSLog("[DS4Mate/Qwen] ⚠️ 语音会话异常：%@", notice)
            return false
        }
        guard voiceSessionActive(in: ax) else {
            NSLog("[DS4Mate/Qwen] 语音会话没开，不动作（请先在千问里手动开启）")
            return false
        }
        return clickMic(in: ax)
    }

    /// 把千问切到前台并等窗口真的出现在当前桌面
    private func bringQwenToFront(completion: @escaping (Bool) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "/Applications/Qianwen.app"]
        try? task.run()

        var attempts = 0
        func poll() {
            attempts += 1
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
            if front && isQwenWindowOnScreen() {
                NSLog("[DS4Mate/Qwen] 千问已切到当前桌面（第 %d 次轮询）", attempts)
                completion(true)
                return
            }
            if attempts >= 12 {
                NSLog("[DS4Mate/Qwen] 轮询 12 次仍未就绪（前台=%@ 在屏=%@）",
                      front ? "是" : "否", isQwenWindowOnScreen() ? "是" : "否")
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { poll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { poll() }
    }

    /// 切回原来那个应用
    private func restoreFocus(to previous: NSRunningApplication?) {
        guard let previous = previous, previous.bundleIdentifier != bundleID else { return }
        let ok = previous.activate(options: [.activateAllWindows])
        NSLog("[DS4Mate/Qwen] 切回 %@（activate=%d）", previous.localizedName ?? "?", ok ? 1 : 0)
        // activate() 有时带不回别的 Space，再用 LaunchServices 兜一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == self.bundleID {
                if let bid = previous.bundleIdentifier {
                    let t = Process()
                    t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    t.arguments = ["-b", bid]
                    try? t.run()
                    NSLog("[DS4Mate/Qwen] activate 没生效，用 open -b %@ 兜底", bid)
                }
            }
        }
    }

    /// 异步重试找麦克风并点击。Chromium 的 AX 树要等页面渲染完才完整，急不得。
    private func clickMicAsync(_ app: NSRunningApplication, deadline: Date, attempt: Int,
                               completion: @escaping (Bool) -> Void) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 2.0)

        var visited = 0
        var anchors: [(score: Int, element: AXUIElement, text: String)] = []
        collectMicButtons(ax, depth: 0, visited: &visited, into: &anchors)
        let maxY = anchors.map { screenY($0.element) }.max() ?? -1
        if attempt == 1 || !anchors.isEmpty {
            NSLog("[DS4Mate/Qwen] 尝试 %d：节点 %d，语音按钮 %d 个（最靠下 y=%.0f）前台=%@ 在屏=%@",
                  attempt, visited, anchors.count, maxY,
                  NSWorkspace.shared.frontmostApplication?.localizedName ?? "?",
                  isQwenWindowOnScreen() ? "是" : "否")
        }

        if clickMic(in: ax) {
            completion(true)
            return
        }
        guard Date() < deadline else {
            NSLog("[DS4Mate/Qwen] 超时，仍没有麦克风按钮")
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.clickMicAsync(app, deadline: deadline, attempt: attempt + 1, completion: completion)
        }
    }

    /// 千问有没有窗口真的显示在当前桌面上（CGWindowList 只列当前 Space 的窗口）
    private func isQwenWindowOnScreen() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let width = b["Width"] as? CGFloat, let height = b["Height"] as? CGFloat else { continue }
            if width >= 300, height >= 200 { return true }
        }
        return false
    }

    /// 找到麦克风（灰色麦克风那组）并点一下。返回是否点到了。
    ///
    /// 安全前提：真实鼠标点击会落到**最上层窗口**。如果千问不在前台，
    /// 这一下就点到别的 App 上了，所以必须前置校验。
    private func clickMic(in axApp: AXUIElement) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == bundleID else {
            NSLog("[DS4Mate/Qwen] 千问不在前台（当前 %@），不点", front ?? "?")
            return false
        }
        // 前台 ≠ 窗口在当前桌面：千问的窗口可能在别的 Space，
        // 这时真实点击会落到盖在那个坐标上的其他 App，必须拦住。
        guard isQwenWindowOnScreen() else {
            NSLog("[DS4Mate/Qwen] 千问窗口不在当前桌面，不点")
            return false
        }
        guard let mic = micElement(in: axApp) else { return false }

        // 有 AXPress 就直接按（不碰鼠标、不动光标、不受坐标变化影响）
        if hasPressAction(mic) {
            let r = AXUIElementPerformAction(mic, kAXPressAction as CFString)
            NSLog("[DS4Mate/Qwen] 麦克风有 AXPress，直接按 -> %d（%@）",
                  Int(r.rawValue), strings(mic).joined(separator: " | "))
            if r == .success { return true }
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var p = CGPoint.zero
        var s = CGSize.zero
        if AXUIElementCopyAttributeValue(mic, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(mic, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        let center = CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
        NSLog("[DS4Mate/Qwen] 没有 AXPress，鼠标点击麦克风 (%.0f, %.0f)", center.x, center.y)
        clickAt(center)
        return true
    }

    private func hasPressAction(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return false }
        return list.contains(kAXPressAction)
    }

    /// 千问会在输入框上方弹一条提示（如「实时语音连接已中断，请重新开始。」）。
    /// 有这条时麦克风按钮是死的，点也没用，得先重开语音会话。
    private func voiceSessionNotice(in axApp: AXUIElement) -> String? {
        var found: [String] = []
        var visited = 0
        collectNotices(axApp, depth: 0, visited: &visited, into: &found)
        return found.first
    }

    private func collectNotices(_ element: AXUIElement, depth: Int, visited: inout Int, into out: inout [String]) {
        guard depth < 40, visited < 6000, out.count < 3 else { return }
        visited += 1
        let role = roleOf(element)
        if role == "AXStaticText" || role == "AXHeading" {
            let text = strings(element).joined(separator: " ")
            if text.contains("已中断") || text.contains("请重新开始") || text.contains("连接失败") {
                out.append(text)
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectNotices(c, depth: depth + 1, visited: &visited, into: &out) }
    }

    /// 真实鼠标点击：AXGroup 没有 AXPress，只能模拟 HID 点击。点完把光标还给用户原位。
    private func clickAt(_ point: CGPoint) {
        let saved = CGEvent(source: nil)?.location
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else {
            NSLog("[DS4Mate/Qwen] 造鼠标事件失败")
            return
        }
        down.post(tap: .cghidEventTap)
        usleep(45_000)
        up.post(tap: .cghidEventTap)
        let now = CGEvent(source: nil)?.location ?? .zero
        NSLog("[DS4Mate/Qwen] 点击后光标在 (%.0f,%.0f)（期望 %.0f,%.0f）",
              now.x, now.y, point.x, point.y)
        if let s = saved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                CGWarpMouseCursorPosition(s)
            }
        }
    }

    /// 直接把点击投递给千问进程，不经过全局鼠标、不动光标、不怕窗口被盖住
    private func clickAtByPid(_ point: CGPoint, pid: pid_t) -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        down.postToPid(pid)
        usleep(45_000)
        up.postToPid(pid)
        return true
    }

    /// 找麦克风开关。
    ///
    /// 千问同一个按钮在不同模式下 **AX 角色会变**，实测见过两种：
    /// - 语音会话模式：`AXCheckBox「开启 Voice Agent 麦克风」(2405,1417 32x32)`
    /// - 普通聊天模式：`AXGroup(2405,1417 32x32)`，没有 AXPress
    /// 所以不能只认某一种角色，要按「文案含麦克风」优先，几何兜底。
    private func micElement(in axApp: AXUIElement) -> AXUIElement? {
        // ① 文案优先：任何文案里带「麦克风」的可点元素
        var named: [(score: Int, element: AXUIElement, text: String, frame: CGRect)] = []
        var visited = 0
        collectNamed(axApp, depth: 0, visited: &visited, into: &named)
        if let best = named.max(by: { $0.score < $1.score }) {
            NSLog("[DS4Mate/Qwen] 按文案命中麦克风：%@ %@ [%@]",
                  best.text, frameString(best.element), roleOf(best.element))
            return best.element
        }
        NSLog("[DS4Mate/Qwen] 文案没有麦克风，走几何（访问 %d 节点）", visited)

        // ② 几何兜底：底部一排 32x32 控件，最右是语音/发送，它左边那个就是麦克风
        var squares: [(x: CGFloat, y: CGFloat, role: String, element: AXUIElement)] = []
        var v2 = 0
        collectSquares(axApp, depth: 0, visited: &v2, into: &squares)
        guard squares.count >= 2 else {
            NSLog("[DS4Mate/Qwen] 底部控件太少（%d 个，访问 %d 节点）", squares.count, v2)
            return nil
        }
        let maxY = squares.map { $0.y }.max() ?? 0
        let row = squares.filter { abs($0.y - maxY) <= 8 }.sorted { $0.x < $1.x }
        guard row.count >= 2, let rightmost = row.last else {
            NSLog("[DS4Mate/Qwen] 同一行只有 %d 个控件", row.count)
            return nil
        }
        let candidates = row.dropLast().filter { rightmost.x - $0.x >= 18 && rightmost.x - $0.x <= 70 }
        guard let mic = candidates.min(by: { abs(rightmost.x - $0.x) < abs(rightmost.x - $1.x) }) else {
            NSLog("[DS4Mate/Qwen] 最右控件 x=%.0f 左边没有麦克风（同行 %d 个）", rightmost.x, row.count)
            return nil
        }
        NSLog("[DS4Mate/Qwen] 几何命中麦克风 %@ x=%.0f y=%.0f（最右 %@ x=%.0f）",
              mic.role, mic.x, mic.y, rightmost.role, rightmost.x)
        return mic.element
    }

    private func roleOf(_ element: AXUIElement) -> String {
        (attribute(element, kAXRoleAttribute) as? String) ?? "?"
    }

    /// 收集文案命中麦克风/静音的可点元素（尺寸限制放宽，防止角色变化导致漏掉）
    private func collectNamed(_ element: AXUIElement, depth: Int, visited: inout Int,
                              into out: inout [(score: Int, element: AXUIElement, text: String, frame: CGRect)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = roleOf(element)
        if role == "AXCheckBox" || role == "AXButton" || role == "AXGroup" || role == "AXToggle" {
            let text = strings(element).joined(separator: " ")
            var score = 0
            if text.contains("麦克风") || text.contains("话筒") { score = 100 }
            else if text.contains("静音") || text.lowercased().contains("mute") { score = 80 }
            else if text.lowercased().contains("mic") { score = 60 }
            if score > 0 {
                var sizeRef: CFTypeRef?
                var s = CGSize.zero
                if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
                   let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
                    AXValueGetValue(v as! AXValue, .cgSize, &s)
                }
                // 只要小图标按钮，排除整个输入框那种大组
                if s.width > 0, s.width <= 60, s.height > 0, s.height <= 60 {
                    out.append((score, element, text, CGRect(x: screenX(element), y: screenY(element),
                                                             width: s.width, height: s.height)))
                }
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectNamed(c, depth: depth + 1, visited: &visited, into: &out) }
    }

    /// 收集底部一栏里 32x32 左右的控件（麦克风组、语音/发送按钮都是这个尺寸）
    private func collectSquares(_ element: AXUIElement, depth: Int, visited: inout Int,
                                into out: inout [(x: CGFloat, y: CGFloat, role: String, element: AXUIElement)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXGroup" || role == "AXButton" || role == "AXCheckBox" || role == "AXToggle" {
            var sizeRef: CFTypeRef?
            var s = CGSize.zero
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgSize, &s)
            }
            let y = screenY(element)
            // 不写死 y 阈值：窗口可以随便挪。后面只取「最靠下那一行」，工具栏天然在最下面。
            if s.width >= 26, s.width <= 38, s.height >= 26, s.height <= 38 {
                out.append((screenX(element), y, role, element))
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children {
            collectSquares(c, depth: depth + 1, visited: &visited, into: &out)
        }
    }

    private func activateAndClickMic(_ app: NSRunningApplication,
                                     originalSpace: UInt64?,
                                     previous: NSRunningApplication?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "/Applications/Qianwen.app"]
        do { try task.run() } catch {
            NSLog("[DS4Mate/Qwen] open 失败: %@", error.localizedDescription)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.clickMicAsync(app, deadline: Date().addingTimeInterval(6.0), attempt: 1) { ok in
                NSLog("[DS4Mate/Qwen] 切换完成 %d", ok ? 1 : 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let space = originalSpace { SpaceSwitcher.shared.switchToSpace(space) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        previous?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                    }
                }
            }
        }
    }

    /// 自检：在底部一栏做点命中测试，看每个图标位置背后到底是哪个 AX 元素、支持什么动作
    public func probeBottomBar() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let sys = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(sys, 3.0)
            var lastKey = ""
            for x in stride(from: 2350, through: 2510, by: 4) {
                var el: AXUIElement?
                let r = AXUIElementCopyElementAtPosition(sys, Float(x), 1433, &el)
                guard r == .success, let e = el else {
                    NSLog("[DS4Mate/Test] hit x=%d -> 无元素 (err %d)", x, Int(r.rawValue))
                    continue
                }
                let role = (self.attribute(e, kAXRoleAttribute) as? String) ?? "?"
                let text = self.strings(e).joined(separator: " | ")
                let key = "\(role)#\(text)"
                if key == lastKey { continue }   // 同一元素只打一次
                lastKey = key

                var actions: [String] = []
                var names: CFArray?
                if AXUIElementCopyActionNames(e, &names) == .success, let n = names as? [String] {
                    actions = n
                }
                var parentRole = "?"
                if let p = self.attribute(e, kAXParentAttribute) {
                    parentRole = (self.attribute(p as! AXUIElement, kAXRoleAttribute) as? String) ?? "?"
                }
                NSLog("[DS4Mate/Test] hit x=%d role=%@ parent=%@ frame=%@ actions=%@ text=%@",
                      x, role, parentRole, self.frameString(e), actions.joined(separator: ","), text)
            }
            NSLog("[DS4Mate/Test] hit 扫描结束（千问 pid=%d）", app.processIdentifier)
        }
    }

    /// 自检：列出千问所有窗口 + 输入框一带的全部可交互元素（不点击，只观察）
    public func dumpBottomBar() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 3.0)

            // 1. 窗口清单（后台也能读到）
            if let wins = self.attribute(ax, kAXWindowsAttribute) as? [AXUIElement] {
                NSLog("[DS4Mate/Test] 窗口数=%d", wins.count)
                for (i, w) in wins.enumerated() {
                    let title = (self.attribute(w, kAXTitleAttribute) as? String) ?? ""
                    let sub = (self.attribute(w, kAXSubroleAttribute) as? String) ?? ""
                    NSLog("[DS4Mate/Test] window[%d] %@ %@ title=%@", i, sub, self.frameString(w), title)
                }
            }

            // 2. 底部一条（y >= 1300）全部元素
            var items: [(y: CGFloat, x: CGFloat, role: String, frame: String, text: String)] = []
            var visited = 0
            self.collectRegion(ax, depth: 0, visited: &visited, minY: 1300, into: &items)
            NSLog("[DS4Mate/Test] === 底部区域 %d 个元素（访问 %d 节点）===", items.count, visited)
            for it in items.sorted(by: { $0.y > $1.y }) {
                NSLog("[DS4Mate/Test] bottom %@ %@ [%@]", it.role, it.frame, it.text)
            }
        }
    }

    private func collectRegion(_ element: AXUIElement, depth: Int, visited: inout Int, minY: CGFloat,
                               into out: inout [(y: CGFloat, x: CGFloat, role: String, frame: String, text: String)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        let y = screenY(element)
        let interesting = !["AXGroup", "AXUnknown", "AXScrollArea", "AXWebArea", "AXList", "AXSplitGroup",
                            "AXStaticText", "AXWindow", "AXApplication"].contains(role)
        if y >= minY && interesting {
            out.append((y, screenX(element), role, frameString(element), strings(element).joined(separator: " | ")))
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectRegion(c, depth: depth + 1, visited: &visited, minY: minY, into: &out) }
    }

    /// 自检：开启语音会话 → 找麦克风 → AXPress → 再 AXPress，全程打印状态
    public func testAXPressCycle() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let store = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(store, 3.0)
        NSLog("[DS4Mate/Test] 起始：会话=%@", voiceSessionActive(in: store) ? "开" : "关")

        // 没开会话就先点黑圆钮把它开起来（只在这个自检里干）
        if !voiceSessionActive(in: store) {
            guard let circle = rightmostSquare(in: store) else {
                NSLog("[DS4Mate/Test] 找不到右侧圆钮")
                return
            }
            let f = frameOf(circle)
            NSLog("[DS4Mate/Test] 点黑圆钮开语音会话 (%.0f,%.0f)", f.midX, f.midY)
            clickAt(CGPoint(x: f.midX, y: f.midY))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 3.0)
            NSLog("[DS4Mate/Test] 3s 后：会话=%@ 签名=%@",
                  self.voiceSessionActive(in: ax) ? "开" : "关", self.stateSignature())

            guard let mic = self.micElement(in: ax) else {
                NSLog("[DS4Mate/Test] 找不到麦克风")
                return
            }
            NSLog("[DS4Mate/Test] 麦克风 %@ role=%@ 有AXPress=%@ 文案=%@",
                  self.frameString(mic), self.roleOf(mic),
                  self.hasPressAction(mic) ? "是" : "否", self.strings(mic).joined(separator: " | "))

            if self.hasPressAction(mic) {
                let r = AXUIElementPerformAction(mic, kAXPressAction as CFString)
                NSLog("[DS4Mate/Test] AXPress#1 -> %d", Int(r.rawValue))
            } else {
                self.clickAt(CGPoint(x: self.frameOf(mic).midX, y: self.frameOf(mic).midY))
                NSLog("[DS4Mate/Test] 无 AXPress，改用鼠标点击#1")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let ax2 = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(ax2, 3.0)
                NSLog("[DS4Mate/Test] 第一次后：签名=%@", self.stateSignature())
                if let mic2 = self.micElement(in: ax2), self.hasPressAction(mic2) {
                    let r2 = AXUIElementPerformAction(mic2, kAXPressAction as CFString)
                    NSLog("[DS4Mate/Test] AXPress#2 -> %d", Int(r2.rawValue))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NSLog("[DS4Mate/Test] 第二次后：签名=%@", self.stateSignature())
                }
            }
        }
    }

    /// 底部那一排里最靠右的 32x32 控件（语音/发送圆钮）
    private func rightmostSquare(in axApp: AXUIElement) -> AXUIElement? {
        var squares: [(x: CGFloat, y: CGFloat, role: String, element: AXUIElement)] = []
        var visited = 0
        collectSquares(axApp, depth: 0, visited: &visited, into: &squares)
        let maxY = squares.map { $0.y }.max() ?? 0
        return squares.filter { abs($0.y - maxY) <= 8 }.max(by: { $0.x < $1.x })?.element
    }

    /// 自检：验证「投递到进程」能不能真的切换麦克风（不移动光标、不切桌面）
    public func testPostToPid() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 3.0)
        NSLog("[DS4Mate/Test] 会话开着=%@ 签名=%@", voiceSessionActive(in: ax) ? "是" : "否", stateSignature())

        guard let mic = micElement(in: ax) else {
            NSLog("[DS4Mate/Test] 找不到麦克风")
            return
        }
        let f = frameOf(mic)
        let center = CGPoint(x: f.midX, y: f.midY)
        NSLog("[DS4Mate/Test] 麦克风 %@ 中心 (%.0f,%.0f) 前台=%@ 在屏=%@",
              NSStringFromRect(f), center.x, center.y,
              NSWorkspace.shared.frontmostApplication?.localizedName ?? "?",
              isQwenWindowOnScreen() ? "是" : "否")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.clickAtByPid(center, pid: app.processIdentifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                NSLog("[DS4Mate/Test] 第 1 次投递后: %@", self.stateSignature())
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = self.clickAtByPid(center, pid: app.processIdentifier)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                        NSLog("[DS4Mate/Test] 第 2 次投递后: %@", self.stateSignature())
                        NSLog("[DS4Mate/Test] 投递测试结束")
                    }
                }
            }
        }
    }

    /// 千问是否处于「语音会话已开启」状态：有「关闭语音会话」按钮就是开着
    private func voiceSessionActive(in axApp: AXUIElement) -> Bool {
        var found = false
        var visited = 0
        collectVoiceSessionButton(axApp, depth: 0, visited: &visited, found: &found)
        return found
    }

    private func collectVoiceSessionButton(_ element: AXUIElement, depth: Int, visited: inout Int, found: inout Bool) {
        guard depth < 40, visited < 8000, !found else { return }
        visited += 1
        let role = roleOf(element)
        if role == "AXButton" || role == "AXCheckBox" {
            let text = strings(element).joined(separator: " ")
            if text.contains("关闭语音会话") || text.contains("结束语音") || text.contains("挂断") {
                found = true
                return
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectVoiceSessionButton(c, depth: depth + 1, visited: &visited, found: &found) }
    }

    private func frameOf(_ element: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var p = CGPoint.zero
        var s = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        return CGRect(origin: p, size: s)
    }

    /// 自检：对比「全局点击」和「投递到进程」两种方式，看哪种真能改变千问的状态
    public func compareClickMethods() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self else { return }
            NSLog("[DS4Mate/Test] 初始状态签名: %@", self.stateSignature())
            self.clickMicRepeatedly(remaining: 3, tag: "全局")
        }
    }

    /// 连续点几次，每次间隔 1.5s，看哪一次开始生效
    private func clickMicRepeatedly(remaining: Int, tag: String) {
        guard remaining > 0 else {
            NSLog("[DS4Mate/Test] 连点结束")
            return
        }
        clickMicOnce(byPid: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("[DS4Mate/Test] %@第 %d 次后: %@", tag, 4 - remaining, self.stateSignature())
                self.clickMicRepeatedly(remaining: remaining - 1, tag: tag)
            }
        }
    }

    private func clickMicOnce(byPid: Bool, completion: @escaping () -> Void) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            completion()
            return
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 2.0)
        guard let mic = micElement(in: ax) else {
            NSLog("[DS4Mate/Test] 找不到麦克风")
            completion()
            return
        }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var p = CGPoint.zero
        var s = CGSize.zero
        if AXUIElementCopyAttributeValue(mic, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(mic, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        let center = CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
        NSLog("[DS4Mate/Test] %@ 点击 (%.0f,%.0f)", byPid ? "投递" : "全局", center.x, center.y)
        if byPid {
            _ = clickAtByPid(center, pid: app.processIdentifier)
        } else {
            clickAt(center)
        }
        completion()
    }

    /// 状态指纹：把底部那排带文案的控件 + 麦克风角色拼起来，状态一变字符串就变
    private func stateSignature() -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return "千问未运行"
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 2.0)
        var parts: [(x: CGFloat, text: String, role: String)] = []
        var visited = 0
        collectSignatureParts(ax, depth: 0, visited: &visited, into: &parts)
        let row = parts.filter { $0.x > 2300 }.sorted { $0.x < $1.x }
        let desc = row.map { "\($0.role):\($0.text.isEmpty ? "-" : $0.text)" }.joined(separator: " | ")
        return "节点\(visited) [\(desc)]"
    }

    private func collectSignatureParts(_ element: AXUIElement, depth: Int, visited: inout Int,
                                       into out: inout [(x: CGFloat, text: String, role: String)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = roleOf(element)
        if role == "AXButton" || role == "AXCheckBox" || role == "AXGroup" || role == "AXImage" {
            var sizeRef: CFTypeRef?
            var s = CGSize.zero
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
                AXValueGetValue(v as! AXValue, .cgSize, &s)
            }
            if s.width >= 14, s.width <= 40, s.height <= 40, screenY(element) > 1400, screenY(element) < 1460 {
                out.append((screenX(element), strings(element).first ?? "", role))
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectSignatureParts(c, depth: depth + 1, visited: &visited, into: &out) }
    }

    /// 自检：找带「麦克风」的 AXCheckBox，读状态 → AXPress → 再读状态。
    /// 如果这条路通，就彻底不需要鼠标模拟了。
    public func testMicCheckbox() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 3.0)

            guard let cb = self.findMicCheckbox(in: ax) else {
                NSLog("[DS4Mate/Test] 没找到麦克风 checkbox")
                return
            }
            NSLog("[DS4Mate/Test] 命中 checkbox: %@ %@ 状态=%@ actions=%@",
                  self.frameString(cb), self.strings(cb).joined(separator: " | "),
                  self.checkboxState(cb), self.actions(of: cb))

            let r = AXUIElementPerformAction(cb, kAXPressAction as CFString)
            NSLog("[DS4Mate/Test] AXPress -> %d", Int(r.rawValue))

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let ax2 = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(ax2, 3.0)
                if let cb2 = self.findMicCheckbox(in: ax2) {
                    NSLog("[DS4Mate/Test] 点击后状态=%@ 文案=%@",
                          self.checkboxState(cb2), self.strings(cb2).joined(separator: " | "))
                } else {
                    NSLog("[DS4Mate/Test] 点击后找不到 checkbox 了")
                }
            }
        }
    }

    private func actions(of element: AXUIElement) -> String {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return "-" }
        return list.joined(separator: ",")
    }

    private func checkboxState(_ element: AXUIElement) -> String {
        var parts: [String] = []
        if let v = attribute(element, kAXValueAttribute) {
            parts.append("value=\(v)")
        }
        if let s = attribute(element, "AXSelected") {
            parts.append("selected=\(s)")
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " ")
    }

    /// 找麦克风开关：优先 AXCheckBox，文案里带「麦克风」
    private func findMicCheckbox(in axApp: AXUIElement) -> AXUIElement? {
        var found: [(score: Int, element: AXUIElement, text: String)] = []
        var visited = 0
        collectCheckboxes(axApp, depth: 0, visited: &visited, into: &found)
        NSLog("[DS4Mate/Test] checkbox 候选 %d 个（访问 %d 节点）", found.count, visited)
        for f in found {
            NSLog("[DS4Mate/Test]   候选 score=%d %@ [%@]", f.score, frameString(f.element), f.text)
        }
        return found.max(by: { $0.score < $1.score })?.element
    }

    private func collectCheckboxes(_ element: AXUIElement, depth: Int, visited: inout Int,
                                   into out: inout [(score: Int, element: AXUIElement, text: String)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXCheckBox" || role == "AXToggle" || role == "AXSwitch" {
            let text = strings(element).joined(separator: " ")
            var score = 0
            if text.contains("麦克风") { score = 100 }
            else if text.contains("静音") { score = 60 }
            else if text.contains("mic") || text.contains("mute") { score = 50 }
            if score > 0 { out.append((score, element, text)) }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectCheckboxes(c, depth: depth + 1, visited: &visited, into: &out) }
    }

    /// 自检：把麦克风附近区域里**所有** AX 元素连同精确坐标打出来（不限尺寸/角色）。
    /// 用来对比「麦克风开」和「麦克风关」两种状态下几何有没有变化。
    public func dumpMicRegion() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 3.0)

            // 先用「32x32 最下一行」找到大致区域，再把这个区域里的东西全列出来
            var squares: [(x: CGFloat, y: CGFloat, role: String, element: AXUIElement)] = []
            var visited = 0
            self.collectSquares(ax, depth: 0, visited: &visited, into: &squares)
            let maxY = squares.map { $0.y }.max() ?? 0
            let row = squares.filter { abs($0.y - maxY) <= 8 }.sorted { $0.x < $1.x }
            guard let rightmost = row.last else {
                NSLog("[DS4Mate/Test] region: 找不到最右控件")
                return
            }
            NSLog("[DS4Mate/Test] === region 快照（最右控件 %@ x=%.0f y=%.0f，同行 %d 个）===",
                  rightmost.role, rightmost.x, rightmost.y, row.count)
            for r in row {
                NSLog("[DS4Mate/Test] 行内 %@ x=%.1f y=%.1f", r.role, r.x, r.y)
            }

            // 扫这个矩形里的所有元素
            let rect = CGRect(x: rightmost.x - 140, y: rightmost.y - 40, width: 200, height: 80)
            var all: [(y: CGFloat, x: CGFloat, role: String, w: CGFloat, h: CGFloat, text: String)] = []
            var v2 = 0
            self.collectInRect(ax, depth: 0, visited: &v2, rect: rect, into: &all)
            for e in all.sorted(by: { $0.x < $1.x }) {
                NSLog("[DS4Mate/Test] region %@ x=%.1f y=%.1f %.0fx%.0f [%@]",
                      e.role, e.x, e.y, e.w, e.h, e.text)
            }
        }
    }

    private func collectInRect(_ element: AXUIElement, depth: Int, visited: inout Int, rect: CGRect,
                               into out: inout [(y: CGFloat, x: CGFloat, role: String, w: CGFloat, h: CGFloat, text: String)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var p = CGPoint.zero
        var s = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let v = sizeRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if rect.contains(CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)), s.width > 0, s.height > 0 {
            out.append((p.y, p.x, role, s.width, s.height, strings(element).joined(separator: " | ")))
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectInRect(c, depth: depth + 1, visited: &visited, rect: rect, into: &out) }
    }

    /// 自检：只点一次麦克风（用来观察开/关两个方向）
    public func singleMicClick() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        NSLog("[DS4Mate/Test] 单次点击前：前台=%@ 在屏=%@",
              NSWorkspace.shared.frontmostApplication?.localizedName ?? "?",
              isQwenWindowOnScreen() ? "是" : "否")
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            self.clickMicAsync(app, deadline: Date().addingTimeInterval(8.0), attempt: 1) { ok in
                NSLog("[DS4Mate/Test] 单次点击 %d", ok ? 1 : 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let ax = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(ax, 3.0)
                    self.dumpBottomBarQuiet(ax, tag: "单次点击后")
                }
            }
        }
    }

    /// 自检：激活千问 → 点一次麦克风 → 观察 → 再点一次还原
    public func inspectAndToggleMic() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            NSLog("[DS4Mate/Test] 千问未运行")
            return
        }
        NSLog("[DS4Mate/Test] AX 已授权=%d", AXIsProcessTrusted() ? 1 : 0)

        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "/Applications/Qianwen.app"]
        try? t.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            self.clickMicAsync(app, deadline: Date().addingTimeInterval(7.0), attempt: 1) { ok in
                NSLog("[DS4Mate/Test] 第 1 次点击 %d", ok ? 1 : 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let ax2 = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(ax2, 3.0)
                    self.dumpBottomBarQuiet(ax2, tag: "第1次点击后")
                    if self.clickMic(in: ax2) { NSLog("[DS4Mate/Test] 第 2 次点击完成") }
                }
            }
        }
    }

    /// 只打底部右侧那一小块的按钮/组，供点击前后对比
    private func dumpBottomBarQuiet(_ ax: AXUIElement, tag: String) {
        var rows: [(y: CGFloat, x: CGFloat, role: String, frame: String, text: String)] = []
        var visited = 0
        collectRegion(ax, depth: 0, visited: &visited, minY: 1350, into: &rows)
        let tail = rows.filter { $0.x > 2200 && $0.y < 1600 }.sorted { $0.x < $1.x }
        NSLog("[DS4Mate/Test] === %@ 右下角 %d 个 ===", tag, tail.count)
        for r in tail {
            NSLog("[DS4Mate/Test] %@ %@ %@ [%@]", tag, r.role, r.frame, r.text)
        }
    }

    /// 把界面上所有 AXButton 连同位置/文案打出来，按 y 从大到小
    private func inspectButtons(_ ax: AXUIElement, tag: String) {
        var found: [(y: CGFloat, x: CGFloat, text: String, score: Int)] = []
        var visited = 0
        collectAllButtons(ax, depth: 0, visited: &visited, into: &found)
        NSLog("[DS4Mate/Test] === %@：共 %d 个按钮（访问 %d 节点）===", tag, found.count, visited)
        for b in found.sorted(by: { $0.y > $1.y }).prefix(20) {
            NSLog("[DS4Mate/Test] %@ y=%.0f x=%.0f score=%d [%@]",
                  tag, b.y, b.x, b.score, b.text)
        }
    }

    private func collectAllButtons(_ element: AXUIElement, depth: Int, visited: inout Int,
                                   into out: inout [(y: CGFloat, x: CGFloat, text: String, score: Int)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXButton" {
            let text = strings(element).joined(separator: " | ")
            out.append((screenY(element), screenX(element), text, micScore(text)))
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectAllButtons(c, depth: depth + 1, visited: &visited, into: &out) }
    }

    /// 打印元素全部属性（用来找按钮的「开/关」状态标识）
    private func dumpButtonState(near element: AXUIElement, tag: String) {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else {
            NSLog("[DS4Mate/Test] %@ 取不到属性名", tag)
            return
        }
        for n in list {
            let v = attribute(element, n)
            let desc = (v as? String) ?? String(describing: v ?? "nil" as AnyObject)
            NSLog("[DS4Mate/Test] %@ attr %@ = %@", tag, n, desc)
        }
    }

    private func screenX(_ element: AXUIElement) -> CGFloat {
        var posRef: CFTypeRef?
        var p = CGPoint.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        return p.x
    }

    /// 千问输入框右侧那个麦克风按钮，AX 文案也叫「语音聊天」，和侧边栏入口**同名**。
    /// 只能靠位置区分：输入框在窗口底部，它的 y 坐标明显更大。
    private func micScore(_ text: String) -> Int {
        let t = text.lowercased()
        if t.isEmpty { return 0 }
        if t.contains("麦克风") || t.contains("话筒") { return 100 }
        if t.contains("静音") || t.contains("mute") { return 80 }
        if t.contains("新语音") || t.contains("新建语音") { return 0 }   // 新建入口，不是麦克风
        if t.contains("语音聊天") || t.contains("语音通话") { return 90 }
        if t.contains("mic") { return 70 }
        return 0
    }

    private func screenY(_ element: AXUIElement) -> CGFloat {
        var posRef: CFTypeRef?
        var p = CGPoint.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let v = posRef, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        return p.y
    }

    private func bestMicButton(in axApp: AXUIElement) -> (score: Int, element: AXUIElement, text: String)? {
        var candidates: [(score: Int, element: AXUIElement, text: String)] = []
        var visited = 0
        collectMicButtons(axApp, depth: 0, visited: &visited, into: &candidates)

        guard !candidates.isEmpty else {
            NSLog("[DS4Mate/Qwen] 麦克风候选为空（访问 %d 节点）", visited)
            return nil
        }
        // 同名的「语音聊天」有两个，选最靠下的那个（输入框在底部）
        candidates.sort { screenY($0.element) > screenY($1.element) }
        for c in candidates.prefix(3) {
            NSLog("[DS4Mate/Qwen] mic 候选 y=%.0f score=%d text=%@",
                  screenY(c.element), c.score, c.text)
        }
        return candidates.first
    }

    private func collectMicButtons(_ element: AXUIElement, depth: Int, visited: inout Int,
                                   into out: inout [(score: Int, element: AXUIElement, text: String)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXButton" {
            let text = strings(element).joined(separator: " ")
            let s = micScore(text)
            if s > 0 { out.append((s, element, text)) }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { collectMicButtons(c, depth: depth + 1, visited: &visited, into: &out) }
    }

    private func activateAndPressMic(_ app: NSRunningApplication,
                                     originalSpace: UInt64?,
                                     previous: NSRunningApplication?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "/Applications/Qianwen.app"]
        do { try task.run() } catch {
            NSLog("[DS4Mate/Qwen] open 失败: %@", error.localizedDescription)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 2.0)
            if let btn = self.bestMicButton(in: ax) {
                let r = AXUIElementPerformAction(btn.element, kAXPressAction as CFString)
                NSLog("[DS4Mate/Qwen] mic press \"%@\" -> %d", btn.text, Int(r.rawValue))
            } else {
                NSLog("[DS4Mate/Qwen] 激活后仍找不到麦克风按钮")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let space = originalSpace { SpaceSwitcher.shared.switchToSpace(space) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    previous?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
            }
        }
    }

    private func bestButton(in axApp: AXUIElement) -> (score: Int, element: AXUIElement, text: String)? {
        var candidates: [(score: Int, element: AXUIElement, text: String)] = []
        var visited = 0
        collectButtons(axApp, depth: 0, visited: &visited, into: &candidates)

        guard !candidates.isEmpty else {
            NSLog("[DS4Mate/Qwen] 没有候选按钮（访问 %d 节点）", visited)
            return nil
        }

        candidates.sort { $0.score > $1.score }
        for c in candidates.prefix(3) {
            NSLog("[DS4Mate/Qwen] 候选 score=%d text=%@", c.score, c.text)
        }

        guard let best = candidates.first, best.score >= 40 else {
            NSLog("[DS4Mate/Qwen] 最高分不足，放弃")
            return nil
        }
        return best
    }

    // MARK: - 按钮打分
    //
    // 千问界面上有两个带「语音」的按钮：
    //   - 「语音聊天」        ← 通话开关，这才是要点的
    //   - 「通过语音搜索内容」 ← 搜索框的语音输入，点了只会激活语音搜索
    // 之前用 contains("语音") 会命中后者，所以这里改成打分排序。

    /// 千问里带「语音」的按钮不止一个，必须精确区分：
    /// - 「语音聊天」      → 通话开关（唯一正确目标）
    /// - 「新语音聊天」    → 新建语音会话入口，点了会开新对话而不是开关
    /// - 「通过语音搜索内容」→ 搜索框语音输入
    private func score(_ text: String) -> Int {
        let t = text.lowercased()
        if t.isEmpty { return 0 }

        // 去掉 AX 拼进来的「按钮」后缀再比较
        let core = text
            .replacingOccurrences(of: "按钮", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // 搜索相关直接排除
        if t.contains("搜索") || t.contains("search") { return 0 }

        // 精确匹配开关按钮
        if core == "语音聊天" || core == "语音通话" { return 100 }
        if core == "挂断" || core == "结束通话" || core == "结束语音" { return 95 }

        // 新建入口，不是开关，给低分让它排在后面
        if t.contains("新语音") || t.contains("新建语音") { return 20 }

        if core.contains("挂断") || core.contains("结束通话") || core.contains("结束语音") { return 90 }
        if t.contains("语音聊天") || t.contains("语音通话") { return 80 }
        if t.contains("通话") { return 70 }
        if t.contains("语音") { return 50 }
        if t.contains("voice") || t.contains("call") { return 40 }
        return 0
    }

    private func collectButtons(_ element: AXUIElement, depth: Int, visited: inout Int,
                                into out: inout [(score: Int, element: AXUIElement, text: String)]) {
        guard depth < 40, visited < 8000 else { return }
        visited += 1

        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXButton" {
            let text = strings(element).joined(separator: " ")
            let s = score(text)
            if s > 0 {
                out.append((s, element, text))
            }
        }

        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children {
            collectButtons(child, depth: depth + 1, visited: &visited, into: &out)
        }
    }

    // MARK: - AX 遍历

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    private func strings(_ element: AXUIElement) -> [String] {
        var out: [String] = []
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
                    "AXLabel", "AXIdentifier", "AXRoleDescription"] {
            if let v = attribute(element, key) as? String, !v.isEmpty {
                out.append(v)
            }
        }
        return out
    }

    private func findVoiceButton(_ element: AXUIElement, depth: Int, visited: inout Int) -> AXUIElement? {
        guard depth < 40, visited < 6000 else { return nil }
        visited += 1

        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""

        // 只在按钮/可点击元素上做关键词判断
        if role == "AXButton" || role == "AXLink" || role == "AXImage" {
            let text = strings(element).joined(separator: " ").lowercased()
            if text.contains("语音") || text.contains("通话") || text.contains("挂断")
                || text.contains("voice") || text.contains("call") || text.contains("hang") {
                NSLog("[DS4Mate/Qwen] 命中: role=%@ text=%@", role, strings(element).joined(separator: " | "))
                return element
            }
        }

        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findVoiceButton(child, depth: depth + 1, visited: &visited) {
                return found
            }
        }
        return nil
    }

    /// 找不到时把候选按钮打出来，方便定位
    private func dumpButtons(_ element: AXUIElement, depth: Int, limit: Int) {
        guard depth < 40, limit > 0 else { return }
        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXButton" {
            let parts = strings(element)
            if !parts.isEmpty {
                NSLog("[DS4Mate/Qwen]   button: %@", parts.joined(separator: " | "))
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        var remaining = limit
        for child in children where remaining > 0 {
            dumpButtons(child, depth: depth + 1, limit: remaining)
            remaining -= 1
        }
    }
}
