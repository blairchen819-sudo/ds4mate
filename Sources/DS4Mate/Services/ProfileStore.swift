import Foundation

/// Profile 持久化服务。
/// 文件位置：`~/Library/Application Support/DS4Mate/profiles/{name}.json`
public final class ProfileStore {

    public static let shared = ProfileStore()

    private let fileManager: FileManager
    private let profilesDirectory: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.profilesDirectory = appSupport
            .appendingPathComponent("DS4Mate", isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
        try? fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    /// 加载所有 Profile（内置 + 自定义）。
    public func loadAll() -> [Profile] {
        var profiles = BuiltInProfiles.makeAll()

        // 加载用户自定义 Profile
        guard let contents = try? fileManager.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return profiles
        }

        for url in contents where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let profile = try JSONDecoder().decode(Profile.self, from: data)
                // 跳过同 ID 内置 Profile（避免重复）
                if !profiles.contains(where: { $0.id == profile.id }) {
                    profiles.append(profile)
                }
            } catch {
                // 损坏文件备份
                let backup = url.deletingPathExtension()
                    .appendingPathExtension("broken.\(Int(Date().timeIntervalSince1970)).json")
                try? fileManager.moveItem(at: url, to: backup)
            }
        }

        return profiles
    }

    /// 保存用户自定义 Profile（覆盖同名）。
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

    /// 删除用户自定义 Profile。
    public func delete(_ profile: Profile) throws {
        guard !profile.isBuiltin else {
            throw NSError(domain: "DS4Mate", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "内置 Profile 不可删除"
            ])
        }
        let url = profilesDirectory.appendingPathComponent("\(profile.id.uuidString).json")
        try fileManager.removeItem(at: url)
    }

    /// Profiles 目录路径（用于 UI 显示）。
    public var profilesDirectoryPath: String {
        profilesDirectory.path
    }
}
