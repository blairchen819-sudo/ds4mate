import SwiftUI
import AppKit

/// 设置窗口的单例控制器。
///
/// **为什么不用 SwiftUI 的 `Settings { }` scene**
///
/// 本 App 是 LSUIElement 纯菜单栏应用（Info.plist 里 `LSUIElement = true`），
/// 没有 Dock 图标、也没有常规应用菜单条。SwiftUI 在这种场景下**不会**为
/// `Settings` scene 注册 `showSettingsWindow:` 的响应者，于是
/// `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)`
/// 直接返回 `false` —— 既不报错、也不弹窗。
///
/// 用户看到的现象就是「点菜单栏里的设置毫无反应」。
/// macOS 14+ 的 `@Environment(\.openSettings)` 同样依赖 SwiftUI 的 scene 注册，
/// 在 LSUIElement 下不可靠；而本工程 target 是 macOS 13，也不能直接用。
///
/// 所以这里绕开 responder chain，自己持有一个 NSWindow。
/// 窗口关闭后置空，下次打开重新构建 —— 顺带保证 `@State` 里的
/// 触摸板参数从 `TouchpadMouseService` 重新读取，不会显示过期值。
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// 打开（或前置）设置窗口。
    func show(appState: AppState,
              controllerService: ControllerService,
              permissionMonitor: PermissionMonitor) {
        // 菜单栏应用默认不抢焦点，必须先激活自己，否则窗口会开在其他 App 后面
        NSApp.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(appState)
            .environmentObject(controllerService)
            .environmentObject(permissionMonitor)
            .frame(minWidth: 520, minHeight: 440)

        let hosting = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: hosting)
        w.title = Localization.shared.t("settings.window.title")
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    /// 关闭后释放，下次打开重新读取服务里的最新状态
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
