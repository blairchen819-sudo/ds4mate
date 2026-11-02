import Foundation
import SwiftUI
import Combine

/// 应用状态容器（ObservableObject）。
/// 持有所有 Profiles、活动 Profile、连接状态、权限状态。
@MainActor
public final class AppState: ObservableObject {

    @Published public var profiles: [Profile]
    @Published public var activeProfile: Profile?
    @Published public var hasCompletedOnboarding: Bool
    @Published public var showingOnboarding: Bool = false
    @Published public var showMainWindow: Bool = false
    @Published public var selectedProfileID: UUID?

    public let controllerService: ControllerService
    public let permissionMonitor: PermissionMonitor
    public let profileStore: ProfileStore

    public init(
        profileStore: ProfileStore = .shared,
        controllerService: ControllerService = .shared,
        permissionMonitor: PermissionMonitor = .shared
    ) {
        self.profileStore = profileStore
        self.controllerService = controllerService
        self.permissionMonitor = permissionMonitor

        let allProfiles = profileStore.loadAll()
        self.profiles = allProfiles
        self.hasCompletedOnboarding = false  // 先初始化默认值
        self.activeProfile = allProfiles.first(where: { $0.id == BuiltInProfiles.defaultProfileID })
                       ?? allProfiles.first
        self.selectedProfileID = self.activeProfile?.id

        // 加载首启动状态
        if let data = UserDefaults.standard.data(forKey: "ds4mate.runtimeState"),
           let runtime = try? JSONDecoder().decode(AppRuntimeState.self, from: data) {
            self.hasCompletedOnboarding = runtime.hasCompletedOnboarding
            // 恢复上次活动 Profile
            if let lastID = runtime.activeProfileID,
               let restored = allProfiles.first(where: { $0.id == lastID }) {
                self.activeProfile = restored
                self.selectedProfileID = lastID
            }
        }

        // 首次启动显示 Onboarding
        if !hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showingOnboarding = true
            }
        }

        // 把 active profile 推给 controller service
        controllerService.activeProfile = self.activeProfile
        controllerService.isEnabled = true

        // 监听 cycle profile
        NotificationCenter.default.addObserver(
            forName: .ds4mateCycleProfile,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cycleToNextProfile()
        }

        NotificationCenter.default.addObserver(
            forName: .ds4mateOpenMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showMainWindow = true
        }

        // 启动权限轮询
        permissionMonitor.startPolling()
    }

    // MARK: - Profile 操作

    public func selectProfile(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfile = profile
        selectedProfileID = id
        controllerService.activeProfile = profile
        persistRuntime()
    }

    public func cycleToNextProfile() {
        guard !profiles.isEmpty,
              let current = activeProfile,
              let currentIndex = profiles.firstIndex(where: { $0.id == current.id }) else {
            return
        }
        let nextIndex = (currentIndex + 1) % profiles.count
        selectProfile(profiles[nextIndex].id)
    }

    /// 把当前预设另存为一个新的命名预设（复制键位与参数），并切换过去。
    /// 来源可以是内置或自定义；副本一律是非内置、新 UUID，可独立修改。
    @discardableResult
    public func saveActiveProfileAs(name: String) -> Profile? {
        guard let source = activeProfile else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let copy = try? profileStore.saveAs(source, name: uniqueProfileName(trimmed)) else {
            return nil
        }
        profiles.append(copy)
        selectProfile(copy.id)
        return copy
    }

    /// 同名时自动加序号，避免预设列表里出现两个一模一样的名字。
    private func uniqueProfileName(_ base: String) -> String {
        let existing = Set(profiles.map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    public func updateBinding(in profileID: UUID, input: ControllerInput, action: Action) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let isBuiltin = profiles[index].isBuiltin
        if isBuiltin {
            // 内置 Profile 复制为自定义 Profile
            let copy = Profile(
                name: "\(profiles[index].name)（自定义）",
                isBuiltin: false,
                bindings: profiles[index].bindings,
                parameters: profiles[index].parameters
            )
            profiles.append(copy)
            updateBinding(in: copy.id, input: input, action: action)
            selectProfile(copy.id)
        } else {
            if let bIndex = profiles[index].bindings.firstIndex(where: { $0.input == input }) {
                profiles[index].bindings[bIndex].action = action
            } else {
                profiles[index].bindings.append(KeyBinding(input: input, action: action))
            }
            try? profileStore.save(profiles[index])
            if activeProfile?.id == profileID {
                controllerService.activeProfile = profiles[index]
                activeProfile = profiles[index]
            }
        }
    }

    public func resetToBuiltIn() {
        let builtins = BuiltInProfiles.makeAll()
        // 删除所有用户自定义
        for p in profiles where !p.isBuiltin {
            try? profileStore.delete(p)
        }
        profiles = builtins
        selectProfile(BuiltInProfiles.defaultProfileID)
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        showingOnboarding = false
        persistRuntime()
    }

    private func persistRuntime() {
        let state = AppRuntimeState(
            activeProfileID: activeProfile?.id,
            isMappingEnabled: controllerService.isEnabled,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "ds4mate.runtimeState")
        }
    }
}
