import SwiftUI
import AppKit

/// 主窗口：可视化键位编辑器。
struct EditorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @ObservedObject private var i18n = Localization.shared

    @State private var selectedInput: ControllerInput? = nil
    @State private var showingActionPicker = false
    @State private var showingSaveAs = false
    @State private var newProfileName = ""
    @State private var showingResetConfirm = false
    @State private var pendingDeleteProfile: Profile?
    @State private var showingDeleteConfirm = false
    @State private var deleteFailedMessage: String?

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
        .confirmationDialog(
            i18n.t("editor.reset.title"),
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button(i18n.t("editor.reset.confirm", appState.profiles.count), role: .destructive) {
                selectedInput = nil
                appState.resetAllProfiles()
            }
            Button(i18n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(i18n.t("editor.reset.message"))
        }
        .confirmationDialog(
            i18n.t("editor.delete.title", pendingDeleteProfile?.name ?? ""),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(i18n.t("common.delete"), role: .destructive) {
                guard let target = pendingDeleteProfile else { return }
                if !appState.deleteProfile(target.id) {
                    deleteFailedMessage = i18n.t("editor.delete.failed.body")
                }
                pendingDeleteProfile = nil
                selectedInput = nil
            }
            Button(i18n.t("common.cancel"), role: .cancel) { pendingDeleteProfile = nil }
        } message: {
            Text(i18n.t("editor.delete.message"))
        }
        .alert(i18n.t("editor.delete.failed.title"), isPresented: Binding(
            get: { deleteFailedMessage != nil },
            set: { if !$0 { deleteFailedMessage = nil } }
        )) {
            Button(i18n.t("common.ok"), role: .cancel) { deleteFailedMessage = nil }
        } message: {
            Text(deleteFailedMessage ?? "")
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
                Text(i18n.t("editor.live.lastInput", last.input.displayName))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                Text(last.at, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if connected {
                Text(i18n.t("editor.live.hint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(i18n.t("editor.live.disconnected"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }

            Spacer()

            if !connected {
                Button(i18n.t("editor.live.reconnect")) {
                    controllerService.reconnectController()
                }
                .controlSize(.small)
            }

            Text(i18n.t("editor.live.hid", controllerService.hidReportCount))
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
                Text(i18n.t("editor.permission.title"))
                    .font(.callout)
                Text(i18n.t("editor.permission.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(i18n.t("common.openSystemSettings")) {
                permissionMonitor.openAccessibilitySettings()
            }
            Button(i18n.t("common.revealInFinder")) {
                permissionMonitor.revealAppInFinder()
            }
            Button(i18n.t("common.recheck")) {
                permissionMonitor.refresh()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Profile 选择
            Picker(i18n.t("editor.toolbar.profiles"), selection: Binding(
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
                Label(i18n.t("editor.toolbar.next"), systemImage: "arrow.triangle.2.circlepath")
            }
            .help(i18n.t("editor.toolbar.next.help"))

            // 另存为新的命名预设
            Button {
                newProfileName = i18n.t("editor.saveas.defaultName",
                                        appState.activeProfile?.name ?? i18n.t("common.profile"))
                showingSaveAs = true
            } label: {
                Label(i18n.t("editor.toolbar.saveAs"), systemImage: "square.and.arrow.down.on.square")
            }
            .help(i18n.t("editor.toolbar.saveAs.help"))

            // 删除当前预设
            Button(role: .destructive) {
                pendingDeleteProfile = appState.activeProfile
                showingDeleteConfirm = true
            } label: {
                Label(i18n.t("editor.toolbar.delete"), systemImage: "trash")
            }
            .disabled(appState.profiles.count <= 1)
            .help(appState.profiles.count <= 1
                  ? i18n.t("menubar.delete.keepOne")
                  : i18n.t("editor.toolbar.delete.help"))

            // 重置
            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                Label(i18n.t("editor.toolbar.reset"), systemImage: "arrow.uturn.backward")
            }
            .help(i18n.t("editor.toolbar.reset.help"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var saveAsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(i18n.t("editor.saveas.title"))
                .font(.headline)
            Text(i18n.t("editor.saveas.body", appState.activeProfile?.name ?? i18n.t("common.profile")))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(i18n.t("editor.saveas.placeholder"), text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitSaveAs() }

            HStack {
                Spacer()
                Button(i18n.t("common.cancel")) {
                    showingSaveAs = false
                }
                Button(i18n.t("common.save")) {
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
        case .connecting: return i18n.t("common.connecting")
        case .disconnected: return i18n.t("editor.disconnected")
        }
    }

    private func bindingDetailPanel(input: ControllerInput) -> some View {
        let binding = appState.activeProfile?.binding(for: input)
        let action = binding?.action ?? .none
        let isGlobalSwitchKey = controllerService.profileSwitchInput == input
        // 同一个键组合在不同 app 里含义不同，这里把语义查出来按 app 分组展示
        let appSemantics = ShortcutCatalog.groupedMatches(for: action)

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
                        Text(i18n.t("editor.detail.switchKey.warning"))
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
                    Text(i18n.t("editor.detail.currentBinding"))
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
                            Text(action.category.displayName)
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

                // 这条快捷键在对应软件里到底是什么功能
                // （Orca 预设就显示「Orca · 跳转文件」，而不是只丢一个 ⌘P）
                if !appSemantics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(i18n.t("editor.detail.appFunctions"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(appSemantics.enumerated()), id: \.offset) { _, group in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(group.app)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.16))
                                    .clipShape(Capsule())
                                Text(group.titles.joined(separator: " / "))
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                // 编辑入口：只有点这里才会打开动作选择器
                Button {
                    showingActionPicker = true
                } label: {
                    Label(i18n.t("editor.detail.edit"), systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(i18n.t("editor.detail.edit.help"))

                Button {
                    if let profile = appState.activeProfile {
                        appState.updateBinding(in: profile.id, input: input, action: .none)
                    }
                } label: {
                    Label(i18n.t("editor.detail.disable"), systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(action == Action.none)
                .help(i18n.t("editor.detail.disable.help"))

                Spacer(minLength: 0)

                Text(i18n.t("editor.detail.saved", appState.activeProfile?.name ?? i18n.t("common.profile")))
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
            Text(i18n.t("editor.placeholder.title"))
                .font(.headline)
            Text(i18n.t("editor.placeholder.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
