import Foundation

/// PS4 DualShock 4 上的所有可绑定输入。
/// 设计原则：覆盖 macOS GameController 框架的 GCExtendedGamepad + GCDualShockGamepad 全部按键面。
public enum ControllerInput: String, Codable, CaseIterable, Hashable, Sendable {
    // 数字按键
    case cross           // ×
    case circle          // ○
    case square          // □
    case triangle        // △
    case l1
    case r1
    case l3              // 左摇杆按下
    case r3              // 右摇杆按下
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case share
    case options
    case ps              // 居中 Home 键
    case touchpadButton  // 触摸板按压

    // 模拟轴（连续值，需死区处理）
    case leftStickX
    case leftStickY
    case rightStickX
    case rightStickY
    case leftTriggerAxis  // L2 模拟
    case rightTriggerAxis // R2 模拟

    /// 人类可读名称（跟随界面语言）
    public var displayName: String {
        switch self {
        case .cross: return L("input.cross")
        case .circle: return L("input.circle")
        case .square: return L("input.square")
        case .triangle: return L("input.triangle")
        case .l1: return "L1"
        case .r1: return "R1"
        case .l3: return L("input.l3")
        case .r3: return L("input.r3")
        case .dpadUp: return L("input.dpadUp")
        case .dpadDown: return L("input.dpadDown")
        case .dpadLeft: return L("input.dpadLeft")
        case .dpadRight: return L("input.dpadRight")
        case .share: return "Share"
        case .options: return "Options"
        case .ps: return L("input.ps")
        case .touchpadButton: return L("input.touchpadButton")
        case .leftStickX: return L("input.leftStickX")
        case .leftStickY: return L("input.leftStickY")
        case .rightStickX: return L("input.rightStickX")
        case .rightStickY: return L("input.rightStickY")
        case .leftTriggerAxis: return L("input.leftTriggerAxis")
        case .rightTriggerAxis: return L("input.rightTriggerAxis")
        }
    }

    /// 模拟轴（连续值）vs 数字按键
    public var isAnalog: Bool {
        switch self {
        case .leftStickX, .leftStickY, .rightStickX, .rightStickY,
             .leftTriggerAxis, .rightTriggerAxis:
            return true
        default:
            return false
        }
    }

    /// 硬件类型标签（详情面板右上角的胶囊标记）
    public var kindLabel: String {
        switch self {
        case .leftTriggerAxis, .rightTriggerAxis: return L("input.kind.trigger")
        case .leftStickX, .leftStickY, .rightStickX, .rightStickY: return L("input.kind.stickAxis")
        case .touchpadButton: return L("input.kind.touchpad")
        case .l3, .r3: return L("input.kind.stickPress")
        default: return L("input.kind.button")
        }
    }
}
