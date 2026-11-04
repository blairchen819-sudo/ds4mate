import SwiftUI
import AppKit

/// 设置窗口
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @ObservedObject private var i18n = Localization.shared

    @State private var showingResetConfirm = false

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
