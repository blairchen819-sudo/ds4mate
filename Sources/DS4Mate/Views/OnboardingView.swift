import SwiftUI

/// 首次启动引导（4 步 Sheet）
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionMonitor: PermissionMonitor
    @ObservedObject private var i18n = Localization.shared
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
                    Button(i18n.t("onboarding.back")) {
                        currentStep -= 1
                    }
                }
                Spacer()
                if currentStep < 3 {
                    Button(currentStep == 1 && !permissionMonitor.isAccessibilityGranted
                          ? i18n.t("onboarding.next.authorized")
                          : i18n.t("onboarding.next")) {
                        currentStep += 1
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentStep == 1 && !permissionMonitor.isAccessibilityGranted)
                } else {
                    Button(i18n.t("onboarding.start")) {
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
            Text(i18n.t("onboarding.welcome.title"))
                .font(.title)
            Text(i18n.t("onboarding.welcome.body"))
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
            Text(i18n.t("onboarding.permission.title"))
                .font(.title2)
            Text(i18n.t("onboarding.permission.body"))
                .foregroundStyle(.secondary)
            Text(i18n.t("onboarding.permission.inputMonitoring.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: permissionMonitor.isAccessibilityGranted
                      ? "checkmark.circle.fill"
                      : "circle.dashed")
                    .foregroundStyle(permissionMonitor.isAccessibilityGranted ? .green : .secondary)
                Text(permissionMonitor.isAccessibilityGranted
                     ? i18n.t("onboarding.permission.granted")
                     : i18n.t("onboarding.permission.waiting"))
            }
            .font(.callout)
            HStack {
                Button(i18n.t("common.openSystemSettings")) {
                    permissionMonitor.requestAccessibility()
                    permissionMonitor.openAccessibilitySettings()
                }
                Button(i18n.t("common.openInputMonitoringSettings")) {
                    permissionMonitor.openInputMonitoringSettings()
                }
                Button(i18n.t("common.recheck")) {
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
            Text(i18n.t("onboarding.pairing.title"))
                .font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text(i18n.t("onboarding.pairing.step1"))
                Text(i18n.t("onboarding.pairing.step2"))
                Text(i18n.t("onboarding.pairing.step3"))
            }
            .font(.callout)
            Text(i18n.t("onboarding.pairing.footnote"))
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
            Text(i18n.t("onboarding.try.title"))
                .font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text(i18n.t("onboarding.try.line1"))
                Text(i18n.t("onboarding.try.line2"))
                Text(i18n.t("onboarding.try.line3"))
                Text(i18n.t("onboarding.try.line4"))
                Text(i18n.t("onboarding.try.line5"))
            }
            .font(.callout)
            Text(i18n.t("onboarding.try.footnote"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
