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

    /// 语言变化的转发订阅（见 init 内注释）
    private var cancellables = Set<AnyCancellable>()

    public init(
        profileStore: ProfileStore = .shared,
        controllerService: ControllerService = .shared,
        permissionMonitor: PermissionMonitor = .shared
    ) {
        self.profileStore = profileStore
        self.controllerService = controllerService
        self.permissionMonitor = permissionMonitor

        // loadAll() 在目录为空时会自动补一份初始预设，所以这里不会是空列表
        let allProfiles = profileStore.loadAll()
        self.profiles = allProfiles
        self.hasCompletedOnboarding = false  // 先初始化默认值
        self.activeProfile = allProfiles.first
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

        // 语言切换后：
        // ① 转发 objectWillChange —— 窗口标题这类不经过 `@ObservedObject` 的文案
        //    依赖 AppState 的变更通知才会重算；
        // ② 把「还没被改过名的初始预设」改成当前语言的名字（英文界面下叫 Default）。
        Localization.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.objectWillChange.send()
                    self.renameStarterProfileIfUntouched()
                }
            }
            .store(in: &cancellables)

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

        // 首次启动流程：还没选过语言，或者还没走完引导 → 交给调度者弹窗。
        // （OnboardingView 此前从未被任何视图展示，`showingOnboarding` 只被赋值未被消费。）
        if !Localization.shared.hasChosenLanguage || !hasCompletedOnboarding {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self else { return }
                FirstRunCoordinator.shared.start(appState: self)
            }
        }
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
    /// 副本一律是新 UUID，可独立修改。
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

    /// 删除一份预设。至少保留一份，删除最后一份会返回 false。
    /// 删掉正在使用的那份时，自动切到列表里的下一份（末尾则切到前一份）。
    @discardableResult
    public func deleteProfile(_ id: UUID) -> Bool {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let profile = profiles[index]
        do {
            try profileStore.delete(profile)
        } catch {
            return false
        }
        profiles.remove(at: index)

        if activeProfile?.id == id {
            // 先算好要切到的那份：删的是最后一项时取新的最后一项
            let next = profiles[min(index, profiles.count - 1)]
            selectProfile(next.id)
        } else {
            persistRuntime()
        }
        return true
    }

    /// 删除全部预设，并恢复为一份初始预设。
    /// 破坏性操作：会连同用户自己创建的预设一起删掉，调用前必须二次确认。
    public func resetAllProfiles() {
        for p in profiles {
            try? profileStore.delete(p)
        }
        let starter = ProfileStore.makeStarterProfile()
        try? profileStore.save(starter)
        profiles = [starter]
        selectProfile(starter.id)
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        showingOnboarding = false
        persistRuntime()
    }

    /// 首次启动时初始预设先于语言选择被创建，名字会是当时默认语言那套（「默认」）。
    /// 用户选完语言后，如果这份预设还顶着「初始名」且一份都没多，就改成新语言的名字。
    /// 只认「两种语言的初始名」这一个条件——用户自己改过名的预设一律不动。
    public func renameStarterProfileIfUntouched() {
        guard profiles.count == 1, let profile = profiles.first, !profile.isBuiltin else { return }
        let starterNames = Set(AppLanguage.allCases.map { Localization.shared.t("profile.starter", in: $0) })
        guard starterNames.contains(profile.name) else { return }
        let newName = L("profile.starter")
        guard newName != profile.name else { return }

        var renamed = profile
        renamed.name = newName
        try? profileStore.save(renamed)
        profiles = [renamed]
        selectProfile(renamed.id)
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
