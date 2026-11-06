import SwiftUI
import AppKit

@main
struct DS4MateApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var controllerService = ControllerService.shared
    @StateObject private var permissionMonitor = PermissionMonitor.shared

    init() {
        // 启动权限轮询
        permissionMonitor.refresh()
        permissionMonitor.startPolling()

        // 退出前松开所有模拟中的修饰键，避免 Shift/Control/Fn 卡在按下状态
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            EventSynthesizer.shared.releaseAllModifiers()
        }

        runSelfTestIfRequested()
    }

    /// 自检钩子：`DS4_TEST=mic` 启动后自动点一次千问麦克风按钮，把结果打到日志。
    /// 只是为了我自己验收用，正常启动不触发。
    private func runSelfTestIfRequested() {
        guard let test = ProcessInfo.processInfo.environment["DS4_TEST"], !test.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            switch test {
            case "mic":
                QwenVoiceController.shared.inspectAndToggleMic()
            case "mic1":
                QwenVoiceController.shared.singleMicClick()
            case "dump":
                QwenVoiceController.shared.dumpBottomBar()
            case "probe":
                QwenVoiceController.shared.probeBottomBar()
            case "region":
                QwenVoiceController.shared.dumpMicRegion()
            case "cb":
                QwenVoiceController.shared.testMicCheckbox()
            case "cmp":
                QwenVoiceController.shared.compareClickMethods()
            case "pid":
                QwenVoiceController.shared.testPostToPid()
            case "axp":
                QwenVoiceController.shared.testAXPressCycle()
            case "esc":
                let s = CGEventSource(stateID: .hidSystemState)
                CGEvent(keyboardEventSource: s, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                usleep(40_000)
                CGEvent(keyboardEventSource: s, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
                NSLog("[DS4Mate/Test] 已发 Escape")
            case "spaceL", "spaceR":
                let isLeft = (ProcessInfo.processInfo.environment["DS4_TEST"] ?? "") == "spaceL"
                let key: CGKeyCode = isLeft ? 123 : 124
                let src = CGEventSource(stateID: .hidSystemState)
                let before = SpaceSwitcher.shared.currentSpaceID ?? 0
                // 完整修饰键序列：先按 Control，再按方向键
                let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: 59, keyDown: true)!
                ctrlDown.flags = .maskControl
                ctrlDown.post(tap: .cghidEventTap)
                usleep(50_000)
                let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)!
                down.flags = .maskControl
                down.post(tap: .cghidEventTap)
                usleep(50_000)
                let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)!
                up.flags = .maskControl
                up.post(tap: .cghidEventTap)
                usleep(50_000)
                let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: 59, keyDown: false)!
                ctrlUp.flags = []
                ctrlUp.post(tap: .cghidEventTap)
                NSLog("[DS4Mate/Test] 发 %@ 前 space=%llu", isLeft ? "⌃←" : "⌃→", before)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    NSLog("[DS4Mate/Test] 发 %@ 后 space=%llu",
                          isLeft ? "⌃←" : "⌃→", SpaceSwitcher.shared.currentSpaceID ?? 0)
                }
            case "desk", "deskR":
                let dir = (ProcessInfo.processInfo.environment["DS4_TEST"] ?? "") == "deskR" ? 1 : -1
                let sw = SpaceSwitcher.shared
                NSLog("[DS4Mate/Test] 切桌面前 space=%llu 桌面数=%d",
                      sw.currentSpaceID ?? 0, sw.desktopCount)
                _ = sw.switchDesktop(dir)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSLog("[DS4Mate/Test] 切桌面后 space=%llu", sw.currentSpaceID ?? 0)
                }
            case "space":
                // 用 DS4Mate 自己的权限发 ⌃←，验证是否比外部工具更有效
                let src = CGEventSource(stateID: .hidSystemState)
                let before = SpaceSwitcher.shared.currentSpaceID ?? 0
                let down = CGEvent(keyboardEventSource: src, virtualKey: 123, keyDown: true)!
                down.flags = .maskControl
                down.post(tap: .cghidEventTap)
                usleep(40_000)
                let up = CGEvent(keyboardEventSource: src, virtualKey: 123, keyDown: false)!
                up.flags = .maskControl
                up.post(tap: .cghidEventTap)
                NSLog("[DS4Mate/Test] 发 ⌃← 前 space=%llu", before)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    NSLog("[DS4Mate/Test] 发 ⌃← 后 space=%llu",
                          SpaceSwitcher.shared.currentSpaceID ?? 0)
                }
            case "toggle":
                // 走真实链路（和按 Share 键一样），看完整判定过程
                DispatchQueue.main.async {
                    let r = QwenVoiceController.shared.toggleMicrophone()
                    NSLog("[DS4Mate/Test] toggleMicrophone 返回 %d", r ? 1 : 0)
                }
            case "voice":
                NSLog("[DS4Mate/Test] toggleVoice -> %d", QwenVoiceController.shared.toggleVoice() ? 1 : 0)
            default:
                NSLog("[DS4Mate/Test] 未知用例: %@", test)
            }
        }
    }

    // MARK: - 菜单栏标题

    /// 菜单栏显示的预设名，按「显示宽度」裁剪：全角算 2、半角算 1，上限 20
    /// （约 10 个汉字 / 20 个半角字符）。用户起的长名字不裁会把整条菜单栏挤开。
    private var menuBarProfileName: String {
        guard let raw = appState.activeProfile?.name, !raw.isEmpty else { return "" }
        var width = 0
        var out = ""
        for ch in raw {
            let w = Self.isWideCharacter(ch) ? 2 : 1
            if width + w > 20 { return out + "…" }
            width += w
            out.append(ch)
        }
        return out
    }

    /// 全角字符判定：CJK 表意文字、假名、谚文、全角标点等。
    private static func isWideCharacter(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6:
            return true
        default:
            return false
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
                .environmentObject(controllerService)
                .environmentObject(permissionMonitor)
        } label: {
            // 菜单栏：图标 + 当前预设名 +（映射关闭时）暂停标记。
            // 必须写成自定义视图：实测 macOS 26 会把 `Label` / `MenuBarExtra("标题",
            // systemImage:)` 里的标题文字丢掉，只剩图标。HStack 走的是整块视图
            // 光栅化渲染，文字才能显示，且字号与菜单栏其他项一致、无模糊。
            HStack(spacing: 4) {
                Image(systemName: appState.controllerService.connectionState == .disconnected
                      ? "gamecontroller"
                      : "gamecontroller.fill")
                Text(menuBarProfileName)
                if !appState.controllerService.isEnabled {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // 主窗口（可视化键位编辑器）
        Window(L("app.window.editor"), id: "main") {
            EditorView()
                .environmentObject(appState)
                .environmentObject(controllerService)
                .environmentObject(permissionMonitor)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 880, height: 640)
        .windowResizability(.contentMinSize)

        // 设置窗口：**不用** SwiftUI 的 `Settings { }` scene。
        // 本 App 是 LSUIElement 纯菜单栏应用，没有常规应用菜单条，SwiftUI
        // 不会为该 scene 注册 showSettingsWindow: 的响应者，sendAction 静默失败，
        // 表现为「点设置没反应」。改由 SettingsWindowController 自己持有 NSWindow，
        // 入口在菜单栏面板的「设置」按钮。
        // 注意：⌘, 在 LSUIElement 下同样不可用，属预期行为。
    }
}
