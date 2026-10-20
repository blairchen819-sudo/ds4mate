import Foundation

/// Profile 持久化参数。
public struct ProfileParameters: Codable, Hashable, Sendable {
    public var deadzone: Double
    public var cursorSensitivity: Double
    public var scrollSensitivity: Double
    public var fineScrollSensitivity: Double
    public var invertLeftStickX: Bool
    public var invertLeftStickY: Bool
    public var invertRightStickX: Bool
    public var invertRightStickY: Bool
    public var buttonSwapXY: Bool
    /// L2/R2 判定为「按下」的阈值（0...1）。扳机是 0...1 的单调值，
    /// 不像按键有明确的按下瞬间，必须靠阈值模拟。
    public var triggerThreshold: Double

    public init(
        deadzone: Double = 0.05,
        cursorSensitivity: Double = 1.0,
        scrollSensitivity: Double = 1.0,
        fineScrollSensitivity: Double = 0.3,
        invertLeftStickX: Bool = false,
        invertLeftStickY: Bool = false,
        invertRightStickX: Bool = false,
        invertRightStickY: Bool = false,
        buttonSwapXY: Bool = false,
        triggerThreshold: Double = 0.35
    ) {
        self.deadzone = deadzone
        self.cursorSensitivity = cursorSensitivity
        self.scrollSensitivity = scrollSensitivity
        self.fineScrollSensitivity = fineScrollSensitivity
        self.invertLeftStickX = invertLeftStickX
        self.invertLeftStickY = invertLeftStickY
        self.invertRightStickX = invertRightStickX
        self.invertRightStickY = invertRightStickY
        self.buttonSwapXY = buttonSwapXY
        self.triggerThreshold = triggerThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case deadzone, cursorSensitivity, scrollSensitivity, fineScrollSensitivity
        case invertLeftStickX, invertLeftStickY, invertRightStickX, invertRightStickY
        case buttonSwapXY, triggerThreshold
    }

    /// 手写解码：旧版 profile JSON 里没有 triggerThreshold，必须给默认值，
    /// 否则 `decode` 会抛 keyNotFound，用户已有的预设会整份读不出来。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deadzone = try c.decodeIfPresent(Double.self, forKey: .deadzone) ?? 0.05
        cursorSensitivity = try c.decodeIfPresent(Double.self, forKey: .cursorSensitivity) ?? 1.0
        scrollSensitivity = try c.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 1.0
        fineScrollSensitivity = try c.decodeIfPresent(Double.self, forKey: .fineScrollSensitivity) ?? 0.3
        invertLeftStickX = try c.decodeIfPresent(Bool.self, forKey: .invertLeftStickX) ?? false
        invertLeftStickY = try c.decodeIfPresent(Bool.self, forKey: .invertLeftStickY) ?? false
        invertRightStickX = try c.decodeIfPresent(Bool.self, forKey: .invertRightStickX) ?? false
        invertRightStickY = try c.decodeIfPresent(Bool.self, forKey: .invertRightStickY) ?? false
        buttonSwapXY = try c.decodeIfPresent(Bool.self, forKey: .buttonSwapXY) ?? false
        triggerThreshold = try c.decodeIfPresent(Double.self, forKey: .triggerThreshold) ?? 0.35
    }

    public static let defaults = ProfileParameters()
}

/// 一条按键 → 动作 映射。
public struct KeyBinding: Codable, Hashable, Sendable {
    public let input: ControllerInput
    public var action: Action

    public init(input: ControllerInput, action: Action) {
        self.input = input
        self.action = action
    }
}

/// 完整 Profile：一组绑定 + 参数。
public struct Profile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var version: Int
    public var isBuiltin: Bool
    public var bindings: [KeyBinding]
    public var parameters: ProfileParameters

    public init(
        id: UUID = UUID(),
        name: String,
        version: Int = 1,
        isBuiltin: Bool = false,
        bindings: [KeyBinding] = [],
        parameters: ProfileParameters = .defaults
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.isBuiltin = isBuiltin
        self.bindings = bindings
        self.parameters = parameters
    }

    public func binding(for input: ControllerInput) -> KeyBinding? {
        bindings.first(where: { $0.input == input })
    }
}

/// 应用运行时状态（持久化在 UserDefaults，不在 Profile JSON 中）。
public struct AppRuntimeState: Codable, Sendable {
    public var activeProfileID: UUID?
    public var isMappingEnabled: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        activeProfileID: UUID? = nil,
        isMappingEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false
    ) {
        self.activeProfileID = activeProfileID
        self.isMappingEnabled = isMappingEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
