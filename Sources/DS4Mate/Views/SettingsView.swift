import SwiftUI
import AppKit

/// 设置窗口
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @ObservedObject private var i18n = Localization.shared

    @State private var showingResetConfirm = false

    // 触摸板手感参数（@State 让滑块即时响应；真正的值写回 TouchpadMouseService）
    @State private var touchpadEnabled = TouchpadMouseService.shared.isEnabled
    @State private var sensitivity = TouchpadMouseService.shared.config.sensitivity
    @State private var smoothing = TouchpadMouseService.shared.config.smoothing
    @State private var deadzone = TouchpadMouseService.shared.config.deadzoneSpeed

    // 双指手势
    @State private var twoFingerEnabled = TouchpadMouseService.shared.gesture.config.isEnabled
    @State private var scrollScale = TouchpadMouseService.shared.gesture.config.scrollScale
    @State private var zoomScale = TouchpadMouseService.shared.gesture.config.zoomScale
    @State private var invertScroll = TouchpadMouseService.shared.gesture.config.invertScroll

    private func syncFromService() {
        let c = TouchpadMouseService.shared.config
        sensitivity = c.sensitivity
        smoothing = c.smoothing
        deadzone = c.deadzoneSpeed

        let g = TouchpadMouseService.shared.gesture.config
        twoFingerEnabled = g.isEnabled
        scrollScale = g.scrollScale
        zoomScale = g.zoomScale
        invertScroll = g.invertScroll
    }

    /// 一行「标题 + 当前值 + 滑块」
    private func sliderRow(title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           format: String,
                           apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    apply(newValue)
                    TouchpadMouseService.shared.persistConfig()
                }
            ), in: range, step: step)
        }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(i18n.t("settings.tab.general"), systemImage: "gearshape") }
            permissionsTab
                .tabItem { Label(i18n.t("settings.tab.permissions"), systemImage: "lock") }
            aboutTab
                .tabItem { Label(i18n.t("settings.tab.about"), systemImage: "info.circle") }
        }
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Section(i18n.t("settings.mapping.section")) {
                let binding: Binding<Bool> = Binding(
                    get: { controllerService.isEnabled },
                    set: { controllerService.isEnabled = $0 }
                )
                Toggle(i18n.t("settings.mapping.toggle"), isOn: binding)
            }
            Section(i18n.t("settings.touchpad.section")) {
                Toggle(i18n.t("settings.touchpad.toggle"), isOn: $touchpadEnabled)
                    .onChange(of: touchpadEnabled) { value in
                        TouchpadMouseService.shared.isEnabled = value
                        if value { syncFromService() }
                    }

                if touchpadEnabled {
                    sliderRow(title: i18n.t("settings.touchpad.sensitivity"),
                              value: $sensitivity,
                              range: 0.8...6.0,
                              step: 0.1,
                              format: "%.1f×") {
                        TouchpadMouseService.shared.config.sensitivity = $0
                    }
                    sliderRow(title: i18n.t("settings.touchpad.smoothing"),
                              value: $smoothing,
                              range: 0...1,
                              step: 0.05,
                              format: "%.2f") {
                        TouchpadMouseService.shared.config.smoothing = $0
                    }
                    sliderRow(title: i18n.t("settings.touchpad.deadzone"),
                              value: $deadzone,
                              range: 0...30,
                              step: 0.5,
                              format: "%.1f") {
                        TouchpadMouseService.shared.config.deadzoneSpeed = $0
                    }

                    Divider()

                    Toggle(i18n.t("settings.touchpad.twofinger.toggle"),
                           isOn: $twoFingerEnabled)
                        .onChange(of: twoFingerEnabled) { value in
                            TouchpadMouseService.shared.gesture.config.isEnabled = value
                            TouchpadMouseService.shared.persistConfig()
                        }

                    if twoFingerEnabled {
                        sliderRow(title: i18n.t("settings.touchpad.twofinger.scroll"),
                                  value: $scrollScale,
                                  range: 600...6000,
                                  step: 100,
                                  format: "%.0f px") {
                            TouchpadMouseService.shared.gesture.config.scrollScale = $0
                        }
                        sliderRow(title: i18n.t("settings.touchpad.twofinger.zoom"),
                                  value: $zoomScale,
                                  range: 0.3...3.0,
                                  step: 0.1,
                                  format: "%.1f×") {
                            TouchpadMouseService.shared.gesture.config.zoomScale = $0
                        }
                        Toggle(i18n.t("settings.touchpad.twofinger.invert"),
                               isOn: $invertScroll)
                            .onChange(of: invertScroll) { value in
                                TouchpadMouseService.shared.gesture.config.invertScroll = value
                                TouchpadMouseService.shared.persistConfig()
                            }
                        Text(i18n.t("settings.touchpad.twofinger.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Button(i18n.t("settings.touchpad.reset")) {
                        let defaults = PointerConfig()
                        sensitivity = defaults.sensitivity
                        smoothing = defaults.smoothing
                        deadzone = defaults.deadzoneSpeed
                        TouchpadMouseService.shared.config = defaults

                        let g = TwoFingerGestureConfig()
                        twoFingerEnabled = g.isEnabled
                        scrollScale = g.scrollScale
                        zoomScale = g.zoomScale
                        invertScroll = g.invertScroll
                        TouchpadMouseService.shared.gesture.config = g

                        TouchpadMouseService.shared.persistConfig()
                    }
                    LabeledContent(i18n.t("settings.touchpad.diagnostics.label")) {
                        Text(controllerService.touchpadDiagnostics)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if twoFingerEnabled {
                        LabeledContent(i18n.t("settings.touchpad.twofinger.diagnostics")) {
                            Text(TouchpadMouseService.shared.gesture.diagnostics)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(i18n.t("settings.touchpad.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(i18n.t("settings.switch.section")) {
                Picker(i18n.t("settings.switch.picker"), selection: Binding(
                    get: { controllerService.profileSwitchInput },
                    set: { controllerService.profileSwitchInput = $0 }
                )) {
                    Text(i18n.t("settings.switch.none")).tag(ControllerInput?.none)
                    ForEach(ControllerInput.allCases.filter { !$0.isAnalog }, id: \.self) { input in
                        Text(input.displayName).tag(Optional(input))
                    }
                }
                Text(i18n.t("settings.switch.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(i18n.t("settings.language.section")) {
                Picker(i18n.t("settings.language.picker"), selection: Binding(
                    get: { i18n.language },
                    set: { i18n.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                Text(i18n.t("settings.language.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(i18n.t("settings.data.section")) {
                LabeledContent(i18n.t("settings.data.directory")) {
                    Text(appState.profileStore.profilesDirectoryPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button(i18n.t("common.revealInFinder")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: appState.profileStore.profilesDirectoryPath))
                }
            }
            Section(i18n.t("settings.reset.section")) {
                Button(i18n.t("settings.reset.button"), role: .destructive) {
                    showingResetConfirm = true
                }
                Text(i18n.t("settings.reset.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            i18n.t("editor.reset.title"),
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button(i18n.t("editor.reset.confirm", appState.profiles.count), role: .destructive) {
                appState.resetAllProfiles()
            }
            Button(i18n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(i18n.t("settings.reset.confirm.message"))
        }
    }

    private var permissionsTab: some View {
        Form {
            Section(i18n.t("settings.permissions.section")) {
                HStack {
                    Image(systemName: permissionMonitor.isAccessibilityGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissionMonitor.isAccessibilityGranted ? .green : .orange)
                    Text(permissionMonitor.isAccessibilityGranted
                         ? i18n.t("settings.permissions.granted")
                         : i18n.t("settings.permissions.denied"))
                }
                Text(i18n.t("settings.permissions.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(i18n.t("common.openSystemSettings")) {
                        permissionMonitor.openAccessibilitySettings()
                    }
                    Button(i18n.t("common.recheck")) {
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
            Text(i18n.t("settings.about.tagline"))
                .font(.callout)
                .multilineTextAlignment(.center)
            Divider()
            Text("MIT License")
                .font(.caption)
            Link(i18n.t("settings.about.source"), destination: URL(string: "https://github.com/blairchen819-sudo/ds4mate")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
