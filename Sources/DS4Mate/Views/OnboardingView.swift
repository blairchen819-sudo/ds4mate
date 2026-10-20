import SwiftUI

/// 首次启动引导（4 步 Sheet）
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // 进度条
            ProgressView(value: Double(currentStep + 1), total: 4)
                .padding(.horizontal, 32)
                .padding(.top, 24)

            // 步骤内容
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: permissionStep
                case 2: pairingStep
                case 3: tryStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            // 底部按钮
            HStack {
                if currentStep > 0 {
                    Button("上一步") {
                        currentStep -= 1
                    }
                }
                Spacer()
                if currentStep < 3 {
                    Button(currentStep == 1 && !permissionMonitor.isAccessibilityGranted
                          ? "已授权，继续"
                          : "下一步") {
                        currentStep += 1
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentStep == 1 && !permissionMonitor.isAccessibilityGranted)
                } else {
                    Button("开始使用") {
                        appState.completeOnboarding()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 440)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller.fill")
                .imageScale(.large)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("欢迎使用 DS4Mate")
                .font(.title)
            Text("把 PS4 DualShock 4 手柄变成 Mac 的鼠标和键盘遥控器。\n接下来我们花 1 分钟配置一下。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield")
                .imageScale(.large)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("授予辅助功能权限")
                .font(.title2)
            Text("DS4Mate 通过 macOS 的「辅助功能」权限向系统注入鼠标和键盘事件。这是 macOS 的安全机制，无法绕过。")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: permissionMonitor.isAccessibilityGranted
                      ? "checkmark.circle.fill"
                      : "circle.dashed")
                    .foregroundStyle(permissionMonitor.isAccessibilityGranted ? .green : .secondary)
                Text(permissionMonitor.isAccessibilityGranted
                     ? "已授权 ✓"
                     : "等待授权…（去系统设置中勾选 DS4Mate.app）")
            }
            .font(.callout)
            HStack {
                Button("打开系统设置") {
                    permissionMonitor.requestAccessibility()
                    permissionMonitor.openAccessibilitySettings()
                }
                Button("重新检测") {
                    permissionMonitor.refresh()
                }
            }
        }
    }

    private var pairingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .imageScale(.large)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("配对 PS4 手柄")
                .font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text("1. 长按手柄上的 Share 键 + PS 键，直到灯条快速闪烁")
                Text("2. 打开「系统设置 → 蓝牙」")
                Text("3. 在设备列表中选择「DUALSHOCK 4 Wireless Controller」")
            }
            .font(.callout)
            Text("配对成功后，DS4Mate 会自动连接。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "hand.point.up.left")
                .imageScale(.large)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("试试默认映射")
                .font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text("• 推动右摇杆 = 移动鼠标")
                Text("• 推动左摇杆 = 滚轮滚动")
                Text("• 按 × = 鼠标左键")
                Text("• 按 ○ = 鼠标右键")
                Text("• 按 Options 1 秒 = 退出 DS4Mate")
            }
            .font(.callout)
            Text("所有按键都可以在「键位编辑器」中重新映射。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
