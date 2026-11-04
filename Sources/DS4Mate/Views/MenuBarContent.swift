import SwiftUI
import AppKit

/// 菜单栏下拉内容。
struct MenuBarContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var i18n = Localization.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 状态行
            statusHeader

            Divider()

            // Profile 切换
            HStack {
                Text(i18n.t("menubar.profiles"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.cycleToNextProfile()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help(i18n.t("menubar.cycle.help"))
            }
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
                Label(i18n.t("menubar.mapping.toggle"), systemImage: "switch.2")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 打开主窗口
            Button(action: {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Label(i18n.t("menubar.openEditor"), systemImage: "rectangle.grid.2x2")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 打开设置窗口（菜单栏 App 没有常规应用菜单，必须给个显式入口）
            Button(action: {
                openSettingsWindow()
            }) {
                Label(i18n.t("menubar.settings"), systemImage: "gearshape")
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
                Label(i18n.t("menubar.quit"), systemImage: "power")
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
                    Text(i18n.t("menubar.activeProfile", profile.name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let last = controllerService.lastInput {
                    Text(i18n.t("menubar.lastInput", last.input.displayName, timeAgo(last.at)))
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(i18n.t("menubar.lastInput.waiting"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(i18n.t("menubar.hid", controllerService.hidReportCount, controllerService.hidStatus))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case .disconnected = controllerService.connectionState {
                    Text(i18n.t("menubar.wake"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
                .help(i18n.t("menubar.reconnect.help"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 1 { return i18n.t("menubar.time.justNow") }
        if seconds < 60 { return i18n.t("menubar.time.seconds", seconds) }
        return i18n.t("menubar.time.minutes", seconds / 60)
    }

    private var isDisconnected: Bool {
        if case .disconnected = controllerService.connectionState { return true }
        return false
    }

    /// 手柄已连接但收不到任何数据包 —— macOS 的「输入监控」没授权。
    /// 这跟「辅助功能」是两项独立权限，只给辅助功能只能控制别的 App，收不到手柄。
    private var inputMonitoringWarning: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(i18n.t("menubar.inputMonitoring.title"))
                .font(.caption2)
                .foregroundStyle(.orange)
                .bold()
            Text(i18n.t("menubar.inputMonitoring.body"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text(i18n.t("menubar.inputMonitoring.button"))
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
        case .connecting: return i18n.t("common.connecting")
        case .disconnected: return i18n.t("menubar.disconnected")
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        HStack(spacing: 8) {
            Button(action: { appState.selectProfile(profile.id) }) {
                HStack {
                    Image(systemName: appState.activeProfile?.id == profile.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(appState.activeProfile?.id == profile.id ? Color.accentColor : .secondary)
                    Text(profile.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 删除：最后一份不允许删，避免掉进「一份预设都没有」的死状态
            Button {
                confirmDelete(profile)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(appState.profiles.count <= 1)
            .opacity(appState.profiles.count <= 1 ? 0.25 : 0.55)
            .help(appState.profiles.count <= 1
                  ? i18n.t("menubar.delete.keepOne")
                  : i18n.t("menubar.delete.help", profile.name))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contextMenu {
            Button(i18n.t("menubar.delete.menu")) { confirmDelete(profile) }
                .disabled(appState.profiles.count <= 1)
        }
    }

    /// 菜单栏弹窗里用 AppKit 的模态确认框：SwiftUI 的 confirmationDialog 挂在
    /// MenuBarExtra 这种临时窗口上时，偶尔会随弹窗收起而不显示，用 NSAlert 更稳。
    private func confirmDelete(_ profile: Profile) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = i18n.t("menubar.delete.title", profile.name)
        alert.informativeText = i18n.t("menubar.delete.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: i18n.t("common.delete"))
        alert.addButton(withTitle: i18n.t("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if !appState.deleteProfile(profile.id) {
            let failure = NSAlert()
            failure.messageText = i18n.t("menubar.delete.failed.title")
            failure.informativeText = i18n.t("menubar.delete.failed.body")
            failure.alertStyle = .warning
            failure.addButton(withTitle: i18n.t("common.ok"))
            failure.runModal()
        }
    }

    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(i18n.t("menubar.permission.title"))
                        .font(.callout)
                    Text(i18n.t("menubar.permission.body"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // 280pt 宽的面板放不下三个并排按钮（英文更放不下），
            // 主按钮单独一行，剩下两个并排在第二行。
            VStack(alignment: .leading, spacing: 4) {
                Button(i18n.t("common.openSystemSettings")) {
                    permissionMonitor.openAccessibilitySettings()
                }
                HStack(spacing: 8) {
                    Button(i18n.t("common.revealInFinder")) {
                        permissionMonitor.revealAppInFinder()
                    }
                    Button(i18n.t("common.recheck")) {
                        permissionMonitor.refresh()
                    }
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
        if let window = NSApp.windows.first(where: { $0.title == L("app.window.editor") }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    /// 打开 SwiftUI 的「设置」窗口。
    /// 菜单栏 App（LSUIElement）没有常规应用菜单，⌘, 在无主窗口时按不到，
    /// 所以显式触发 SwiftUI 为 Settings scene 注册的 responder action。
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14+ 是 showSettingsWindow:，13 及更早是 showPreferencesWindow:
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
