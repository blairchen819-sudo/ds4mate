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

    /// 人类可读名称（中文 UI 用）
    public var displayName: String {
        switch self {
        case .cross: return "× 键"
        case .circle: return "○ 键"
        case .square: return "□ 键"
        case .triangle: return "△ 键"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l3: return "L3（左摇杆按下）"
        case .r3: return "R3（右摇杆按下）"
        case .dpadUp: return "D-Pad 上"
        case .dpadDown: return "D-Pad 下"
        case .dpadLeft: return "D-Pad 左"
        case .dpadRight: return "D-Pad 右"
        case .share: return "Share"
        case .options: return "Options"
        case .ps: return "PS 键"
        case .touchpadButton: return "触摸板按键"
        case .leftStickX: return "左摇杆 X"
        case .leftStickY: return "左摇杆 Y"
        case .rightStickX: return "右摇杆 X"
        case .rightStickY: return "右摇杆 Y"
        case .leftTriggerAxis: return "L2 模拟"
        case .rightTriggerAxis: return "R2 模拟"
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
}
