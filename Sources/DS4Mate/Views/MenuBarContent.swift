import SwiftUI
import AppKit

/// 菜单栏下拉内容。
struct MenuBarContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 状态行
            statusHeader

            Divider()

            // Profile 切换
            Text("预设")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ForEach(appState.profiles) { profile in
                profileRow(profile)
            }

            Divider()

            // 启停开关
            Toggle(isOn: Binding(
                get: { controllerService.isEnabled },
                set: { controllerService.isEnabled = $0 }
            )) {
                Label("映射已启用", systemImage: "switch.2")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 打开主窗口
            Button(action: {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Label("打开键位编辑器", systemImage: "rectangle.grid.2x2")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 权限状态
            if !permissionMonitor.isAccessibilityGranted {
                permissionWarning
            }

            Divider()

            // 退出
            Button(action: { NSApp.terminate(nil) }) {
                Label("退出 DS4Mate", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: connectionIcon)
                .foregroundStyle(connectionColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                    .font(.headline)
                if let profile = appState.activeProfile {
                    Text("当前预设：\(profile.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let last = controllerService.lastInput {
                    Text("最近输入：\(last.input.displayName) · \(timeAgo(last.at))")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("最近输入：等待手柄按键…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("HID 报告 \(controllerService.hidReportCount) · \(controllerService.hidStatus)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case .disconnected = controllerService.connectionState {
                    Text("按手柄中间的 PS 键唤醒（× 唤不醒）")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                // 手柄连上了但一个数据包都收不到 = 缺「输入监控」权限，光有辅助功能不够
                if !isDisconnected, controllerService.hidReportCount == 0 {
                    inputMonitoringWarning
                }
            }
            Spacer()
            if case .disconnected = controllerService.connectionState {
                Button {
                    controllerService.reconnectController()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("尝试重新连接手柄")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 1 { return "刚刚" }
        if seconds < 60 { return "\(seconds)秒前" }
        return "\(seconds / 60)分前"
    }

    private var isDisconnected: Bool {
        if case .disconnected = controllerService.connectionState { return true }
        return false
    }

    /// 手柄已连接但收不到任何数据包 —— macOS 的「输入监控」没授权。
    /// 这跟「辅助功能」是两项独立权限，只给辅助功能只能控制别的 App，收不到手柄。
    private var inputMonitoringWarning: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("⚠️ 收不到手柄数据")
                .font(.caption2)
                .foregroundStyle(.orange)
                .bold()
            Text("请在「系统设置 → 隐私与安全性 → 输入监控」里勾选 DS4Mate")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("打开输入监控设置")
                    .font(.caption2)
            }
            .buttonStyle(.link)
        }
        .padding(.top, 2)
    }

    private var connectionIcon: String {
        switch controllerService.connectionState {
        case .connected: return "gamecontroller.fill"
        case .connecting: return "gamecontroller"
        case .disconnected: return "gamecontroller"
        }
    }

    private var connectionColor: Color {
        switch controllerService.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        }
    }

    private var connectionTitle: String {
        switch controllerService.connectionState {
        case .connected(let name): return name
        case .connecting: return "连接中…"
        case .disconnected: return "未连接手柄"
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        Button(action: { appState.selectProfile(profile.id) }) {
            HStack {
                Image(systemName: appState.activeProfile?.id == profile.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(appState.activeProfile?.id == profile.id ? Color.accentColor : .secondary)
                Text(profile.name)
                Spacer()
                if profile.isBuiltin {
                    Text("内置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("未授权辅助功能")
                        .font(.callout)
                    Text("如果系统设置里已有，先移除再重新添加")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("打开系统设置") {
                    permissionMonitor.openAccessibilitySettings()
                }
                Button("在 Finder 中显示") {
                    permissionMonitor.revealAppInFinder()
                }
                Button("重新检测") {
                    permissionMonitor.refresh()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func openMainWindow() {
        // 保留旧实现，但默认走 openWindow 环境
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "DS4Mate 键位编辑器" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
