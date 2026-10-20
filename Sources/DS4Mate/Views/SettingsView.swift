import SwiftUI
import AppKit

/// 设置窗口
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            permissionsTab
                .tabItem { Label("权限", systemImage: "lock") }
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Section("映射") {
                let binding: Binding<Bool> = Binding(
                    get: { controllerService.isEnabled },
                    set: { controllerService.isEnabled = $0 }
                )
                Toggle("启用映射", isOn: binding)
            }
            Section("数据") {
                LabeledContent("Profile 目录") {
                    Text(appState.profileStore.profilesDirectoryPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: appState.profileStore.profilesDirectoryPath))
                }
            }
            Section("重置") {
                Button("恢复内置 3 套预设（删除全部自定义）", role: .destructive) {
                    appState.resetToBuiltIn()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var permissionsTab: some View {
        Form {
            Section("辅助功能（必需）") {
                HStack {
                    Image(systemName: permissionMonitor.isAccessibilityGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissionMonitor.isAccessibilityGranted ? .green : .orange)
                    Text(permissionMonitor.isAccessibilityGranted ? "已授权" : "未授权")
                }
                Text("DS4Mate 通过此权限向 macOS 注入鼠标和键盘事件。授权后无需重启 App，会自动恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("打开系统设置") {
                        permissionMonitor.openAccessibilitySettings()
                    }
                    Button("重新检测") {
                        permissionMonitor.refresh()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .imageScale(.large)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("DS4Mate")
                .font(.title)
            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("把 PS4 DualShock 4 手柄变成 Mac 的鼠标和键盘遥控器")
                .font(.callout)
                .multilineTextAlignment(.center)
            Divider()
            Text("MIT License")
                .font(.caption)
            Link("查看源码", destination: URL(string: "https://github.com/ericmr/ds4mate")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
