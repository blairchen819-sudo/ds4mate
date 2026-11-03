import SwiftUI
import AppKit

/// 主窗口：可视化键位编辑器。
struct EditorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor

    @State private var selectedInput: ControllerInput? = nil
    @State private var showingActionPicker = false
    @State private var showingSaveAs = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(spacing: 0) {
            // 权限条
            if !permissionMonitor.isAccessibilityGranted {
                permissionBar
            }

            // 顶部工具栏
            toolbar

            Divider()

            // 实时输入条：按手柄键立刻能看到反馈，也是排查 HID 链路的窗口
            liveBar

            Divider()

            // 主体：手柄可视化 + 右侧按键详情
            HSplitView {
                ControllerVisual(
                    selectedInput: selectedInput,
                    onSelect: { input in
                        // 单击只负责选中，右侧面板展示当前绑定；
                        // 改键要由用户明确点「编辑」才会打开选择器。
                        selectedInput = input
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let input = selectedInput {
                    bindingDetailPanel(input: input)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                } else {
                    placeholderPanel
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                }
            }
        }
        .sheet(isPresented: $showingActionPicker) {
            if let input = selectedInput {
                ActionPickerView(
                    input: input,
                    currentAction: appState.activeProfile?.binding(for: input)?.action ?? .none,
                    onSelect: { action in
                        if let profile = appState.activeProfile {
                            appState.updateBinding(in: profile.id, input: input, action: action)
                        }
                        showingActionPicker = false
                    },
                    onCancel: {
                        showingActionPicker = false
                    }
                )
                .frame(minWidth: 560, minHeight: 480)
            }
        }
        .sheet(isPresented: $showingSaveAs) {
            saveAsSheet
        }
        .onChange(of: controllerService.lastInput?.at) { _ in
            // 按手柄键时自动选中该键，右侧面板直接显示它的当前映射
            if let input = controllerService.lastInput?.input, !input.isAnalog {
                selectedInput = input
            }
        }
    }

    private var liveBar: some View {
        let connected: Bool = {
            if case .connected = controllerService.connectionState { return true }
            return false
        }()
        return HStack(spacing: 12) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)

            if let last = controllerService.lastInput {
                Text("最近输入：\(last.input.displayName)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                Text(last.at, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if connected {
                Text("按一下手柄上任意键，这里会显示按键名")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("手柄未连接 —— 按手柄中间的 PS 键唤醒（× 唤不醒）")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }

            Spacer()

            if !connected {
                Button("重连手柄") {
                    controllerService.reconnectController()
                }
                .controlSize(.small)
            }

            Text("HID 报告 \(controllerService.hidReportCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(controllerService.hidReportCount > 0 ? .green : .secondary)
            Text(controllerService.hidStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(connected ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
    }

    private var permissionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("未授权辅助功能")
                    .font(.callout)
                Text("如果系统设置里已有 DS4Mate，先移除再重新添加（签名 hash 变了）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        .padding(12)
        .background(Color.orange.opacity(0.1))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Profile 选择
            Picker("预设", selection: Binding(
                get: { appState.selectedProfileID ?? appState.profiles.first?.id ?? UUID() },
                set: { appState.selectProfile($0) }
            )) {
                ForEach(appState.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 180)

            Divider().frame(height: 16)

            // 状态指示
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 切到下一套预设（与手柄上的切换键等效）
            Button {
                appState.cycleToNextProfile()
            } label: {
                Label("下一个预设", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("切换到下一套预设")

            // 另存为新的命名预设
            Button {
                newProfileName = "\(appState.activeProfile?.name ?? "预设") 副本"
                showingSaveAs = true
            } label: {
                Label("另存为…", systemImage: "square.and.arrow.down.on.square")
            }
            .help("把当前预设的键位另存为一个新名字，之后可独立修改")

            // 重置
            Button(role: .destructive) {
                appState.resetToBuiltIn()
            } label: {
                Label("重置全部", systemImage: "arrow.uturn.backward")
            }
            .help("删除所有自定义预设，恢复为内置 3 套")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var saveAsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("另存为新预设")
                .font(.headline)
            Text("会把当前「\(appState.activeProfile?.name ?? "未选择")」的键位和参数复制一份，之后两套互不影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("预设名称", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitSaveAs() }

            HStack {
                Spacer()
                Button("取消") {
                    showingSaveAs = false
                }
                Button("保存") {
                    commitSaveAs()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func commitSaveAs() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = appState.saveActiveProfileAs(name: name)
        newProfileName = ""
        showingSaveAs = false
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
        case .disconnected: return "手柄未连接"
        }
    }

    private func bindingDetailPanel(input: ControllerInput) -> some View {
        let binding = appState.activeProfile?.binding(for: input)
        let action = binding?.action ?? .none
        let isGlobalSwitchKey = controllerService.profileSwitchInput == input

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题：按键名 + 硬件类型
                HStack(alignment: .center) {
                    Text(input.displayName)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text(input.kindLabel)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }

                // 与全局切换键冲突时明确告知，否则用户会以为绑定坏了
                if isGlobalSwitchKey {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("这个键已被设为「全局预设切换键」，按下会切换预设，下面的绑定不会触发。")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                // 当前绑定 + 它对应的快捷功能
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前绑定")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: action.category.iconName)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.displayName)
                                .font(.title3.weight(.medium))
                            Text(action.category.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Text(action.functionDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                )

                // 编辑入口：只有点这里才会打开动作选择器
                Button {
                    showingActionPicker = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("打开动作选择器，给这个键换一个绑定")

                Button {
                    if let profile = appState.activeProfile {
                        appState.updateBinding(in: profile.id, input: input, action: .none)
                    }
                } label: {
                    Label("设为禁用", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(action == Action.none)
                .help("保留这个键，但不触发任何动作")

                Spacer(minLength: 0)

                Text("改动会立即保存到「\(appState.activeProfile?.name ?? "当前预设")」")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var placeholderPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.point.up.left")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("点击手柄上的任一按键")
                .font(.headline)
            Text("右侧会显示它当前绑定的动作和对应功能；\n确认要改再点「编辑」进入动作选择器。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
