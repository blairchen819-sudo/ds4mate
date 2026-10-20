import Foundation
import AppKit
import ApplicationServices

/// Accessibility 权限监测器。
/// 检测当前是否被授权，并 1.5s 间隔轮询防 macOS 更新回退。
public final class PermissionMonitor: ObservableObject {

    public static let shared = PermissionMonitor()

    @Published public private(set) var isAccessibilityGranted: Bool = false

    private var pollingTask: Task<Void, Never>?

    public init() {
        refresh()
    }

    deinit {
        pollingTask?.cancel()
    }

    /// 立即检查权限。
    public func refresh() {
        let trusted = AXIsProcessTrustedWithOptions(nil)
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
        }
    }

    /// 主动弹系统设置（带提示）让用户授权。
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 打开系统设置到「辅助功能」页面。
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 在 Finder 中显示当前 .app（用户可拖到辅助功能列表）
    public func revealAppInFinder() {
        // 找到当前运行的 .app bundle
        if let appPath = Bundle.main.bundlePath as String?,
           !appPath.isEmpty {
            let url = URL(fileURLWithPath: appPath)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// 启动后台 1.5s 轮询，捕获 macOS 更新回退的场景。
    public func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run { self?.refresh() }
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
