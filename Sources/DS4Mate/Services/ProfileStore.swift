import Foundation

/// Profile 持久化服务。
/// 文件位置：`~/Library/Application Support/DS4Mate/profiles/{uuid}.json`
///
/// 应用不再内置固定的几套预设——所有预设都是用户数据，可以随意改名、另存、删除。
/// 唯一的兜底是「初始预设」：目录为空时（首次启动或用户把预设全删了）自动生成一份，
/// 避免出现列表为空、手柄完全没有映射的不可用状态。
public final class ProfileStore {

    public static let shared = ProfileStore()

    private let fileManager: FileManager
    private let profilesDirectory: URL

    /// - Parameter directory: 自定义存储目录（测试用）；默认走 Application Support。
    public init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        if let directory {
            self.profilesDirectory = directory
        } else {
            let appSupport = try! fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.profilesDirectory = appSupport
                .appendingPathComponent("DS4Mate", isDirectory: true)
                .appendingPathComponent("profiles", isDirectory: true)
        }
        try? fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    /// 加载所有预设。目录为空时自动生成一份初始预设。
    public func loadAll() -> [Profile] {
        var profiles: [Profile] = []

        if let contents = try? fileManager.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: nil
        ) {
            for url in contents where url.pathExtension == "json" {
                do {
                    let data = try Data(contentsOf: url)
                    let profile = try JSONDecoder().decode(Profile.self, from: data)
                    profiles.append(profile)
                } catch {
                    // 损坏文件备份，避免每次启动都重试同一份坏数据
                    let backup = url.deletingPathExtension()
                        .appendingPathExtension("broken.\(Int(Date().timeIntervalSince1970)).json")
                    try? fileManager.moveItem(at: url, to: backup)
                }
            }
        }

        if profiles.isEmpty {
            let starter = Self.makeStarterProfile()
            try? save(starter)
            profiles = [starter]
        }

        // 目录枚举顺序不稳定；按名称排序，保证菜单栏列表和「切换下一个」的顺序可预期
        return profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 保存预设（按 UUID 覆盖）。
    public func save(_ profile: Profile) throws {
        guard !profile.isBuiltin else {
            throw NSError(domain: "DS4Mate", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "内置 Profile 不可保存"
            ])
        }
        let url = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: url, options: .atomic)
    }

    /// 以新名字另存为一份独立预设（新 UUID + 复制全部绑定与参数）。
    /// 用于「另存为」：把当前键位保存成一个新的命名预设，之后两套互不影响。
    public func saveAs(_ source: Profile, name: String) throws -> Profile {
        let copy = Profile(
            name: name,
            isBuiltin: false,
            bindings: source.bindings,
            parameters: source.parameters
        )
        try save(copy)
        return copy
    }

    /// 删除预设。
    public func delete(_ profile: Profile) throws {
        guard !profile.isBuiltin else {
            throw NSError(domain: "DS4Mate", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "内置 Profile 不可删除"
            ])
        }
        let url = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        try fileManager.removeItem(at: url)
    }

    /// 初始预设：首次启动（或预设被全部删除）时自动生成。
    /// 内容沿用旧版「默认」那套鼠标/键盘映射，但它就是一份普通预设，可改、可删。
    public static func makeStarterProfile() -> Profile {
        Profile(
            name: "默认",
            isBuiltin: false,
            bindings: [
                .init(input: .leftStickX, action: .scroll),
                .init(input: .leftStickY, action: .scroll),
                .init(input: .rightStickX, action: .mouseMoveCursor),
                .init(input: .rightStickY, action: .mouseMoveCursor),
                .init(input: .leftTriggerAxis, action: .fineScroll),
                .init(input: .rightTriggerAxis, action: .fineScroll),
                .init(input: .cross, action: .mouseLeftClick),
                .init(input: .circle, action: .mouseRightClick),
                .init(input: .square, action: .mouseMiddleClick),
                .init(input: .triangle, action: .mouseDoubleClick),
                .init(input: .l1, action: .systemShortcut(.browserBack)),
                .init(input: .r1, action: .systemShortcut(.browserForward)),
                .init(input: .l3, action: .mouseDragToggle),
                .init(input: .r3, action: .systemShortcut(.launchpad)),
                .init(input: .dpadUp, action: .systemShortcut(.missionControl)),
                .init(input: .dpadDown, action: .systemShortcut(.appExpose)),
                .init(input: .dpadLeft, action: .systemShortcut(.browserBack)),
                .init(input: .dpadRight, action: .systemShortcut(.browserForward)),
                .init(input: .ps, action: .none),  // 默认禁用，避免误触
                .init(input: .share, action: .systemShortcut(.screenshotSelection)),
                .init(input: .touchpadButton, action: .systemShortcut(.missionControl)),
                .init(input: .options, action: .exitApp)
            ]
        )
    }

    /// Profiles 目录路径（用于 UI 显示）。
    public var profilesDirectoryPath: String {
        profilesDirectory.path
    }
}
