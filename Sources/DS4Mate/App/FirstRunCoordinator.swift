import AppKit
import SwiftUI
import Combine

/// 首次启动流程的调度者：先选语言，再走引导。
///
/// 为什么不用 SwiftUI 的 `Window` scene：这个 App 是 `LSUIElement`（菜单栏常驻、
/// 无 Dock 图标），启动时没有任何窗口，而 `openWindow(id:)` 只能在已有视图的
/// environment 里调用。要"启动即弹窗"，直接用 AppKit 的 `NSWindow` 托管
/// SwiftUI 视图是最稳的一条路，同一份代码也顺手把此前从未被展示过的引导页接上。
@MainActor
final class FirstRunCoordinator {

    static let shared = FirstRunCoordinator()

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// 启动入口。已有语言偏好就跳过选择，直接看是否需要引导。
    func start(appState: AppState) {
        if !Localization.shared.hasChosenLanguage {
            presentLanguagePicker { [weak self] in
                self?.closeWindow()
                self?.continueAfterLanguage(appState: appState)
            }
            return
        }
        continueAfterLanguage(appState: appState)
    }

    // MARK: - 步骤

    private func continueAfterLanguage(appState: AppState) {
        guard !appState.hasCompletedOnboarding else { return }
        presentOnboarding(appState: appState)
    }

    private func presentLanguagePicker(onChoose: @escaping () -> Void) {
        let view = LanguagePickerView { language in
            Localization.shared.setLanguage(language)
            onChoose()
        }
        // 标题同时给两种语言：此刻用户还没表态
        present(view, title: "Language · 语言", closable: false)
    }

    private func presentOnboarding(appState: AppState) {
        appState.showingOnboarding = true

        let view = OnboardingView()
            .environmentObject(appState)
            .environmentObject(appState.controllerService)
            .environmentObject(appState.permissionMonitor)

        // 引导页内部调 completeOnboarding() 完成，这里监听状态关窗
        appState.$hasCompletedOnboarding
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.closeWindow()
                }
            }
            .store(in: &cancellables)

        present(view, title: L("app.window.onboarding"), closable: true)
    }

    // MARK: - 窗口

    private func present<Content: View>(_ view: Content, title: String, closable: Bool) {
        closeWindow()

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = closable ? [.titled, .closable] : [.titled]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.center()
        window.setContentSize(hosting.view.fittingSize)

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
