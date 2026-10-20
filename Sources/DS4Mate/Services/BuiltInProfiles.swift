import Foundation

/// 三套内置 Profile（默认 / 媒体 / 演示）。
/// 这些是 Spec §6.5 锁定的默认映射表。
public enum BuiltInProfiles {

    public static let defaultProfileID = UUID(uuidString: "B0B0B0B0-0000-0000-0000-000000000001")!
    public static let mediaProfileID    = UUID(uuidString: "B0B0B0B0-0000-0000-0000-000000000002")!
    public static let presentationID    = UUID(uuidString: "B0B0B0B0-0000-0000-0000-000000000003")!

    public static func makeAll() -> [Profile] {
        [makeDefault(), makeMedia(), makePresentation()]
    }

    public static func makeDefault() -> Profile {
        Profile(
            id: defaultProfileID,
            name: "默认",
            isBuiltin: true,
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
                .init(input: .ps, action: .none),  // 默认禁用（避免误触）
                .init(input: .share, action: .systemShortcut(.screenshotSelection)),
                .init(input: .touchpadButton, action: .systemShortcut(.missionControl)),
                .init(input: .options, action: .exitApp)
            ]
        )
    }

    public static func makeMedia() -> Profile {
        Profile(
            id: mediaProfileID,
            name: "媒体遥控",
            isBuiltin: true,
            bindings: [
                .init(input: .leftStickX, action: .none),
                .init(input: .leftStickY, action: .none),
                .init(input: .rightStickX, action: .mediaKey(.volumeDown)),
                .init(input: .rightStickY, action: .mediaKey(.volumeUp)),
                .init(input: .leftTriggerAxis, action: .mediaKey(.volumeDown)),
                .init(input: .rightTriggerAxis, action: .mediaKey(.volumeUp)),
                .init(input: .cross, action: .mediaKey(.playPause)),
                .init(input: .circle, action: .none),
                .init(input: .square, action: .mediaKey(.previous)),
                .init(input: .triangle, action: .mediaKey(.next)),
                .init(input: .l1, action: .mediaKey(.previous)),
                .init(input: .r1, action: .mediaKey(.next)),
                .init(input: .l3, action: .none),
                .init(input: .r3, action: .none),
                .init(input: .dpadUp, action: .none),
                .init(input: .dpadDown, action: .none),
                .init(input: .dpadLeft, action: .mediaKey(.previous)),
                .init(input: .dpadRight, action: .mediaKey(.next)),
                .init(input: .ps, action: .none),
                .init(input: .share, action: .none),
                .init(input: .touchpadButton, action: .mediaKey(.mute)),
                .init(input: .options, action: .exitApp)
            ]
        )
    }

    public static func makePresentation() -> Profile {
        Profile(
            id: presentationID,
            name: "演示",
            isBuiltin: true,
            bindings: [
                .init(input: .leftStickX, action: .none),
                .init(input: .leftStickY, action: .none),
                .init(input: .rightStickX, action: .mouseMoveCursor),
                .init(input: .rightStickY, action: .mouseMoveCursor),
                .init(input: .leftTriggerAxis, action: .keyPress(keyCode: 115, modifiers: [])), // Page Up
                .init(input: .rightTriggerAxis, action: .keyPress(keyCode: 119, modifiers: [])), // Page Down
                .init(input: .cross, action: .keyPress(keyCode: 124, modifiers: [])), // Right Arrow
                .init(input: .circle, action: .keyPress(keyCode: 53, modifiers: [])), // Escape
                .init(input: .square, action: .keyPress(keyCode: 51, modifiers: [.maskCommand])), // Cmd+H
                .init(input: .triangle, action: .keyPress(keyCode: 48, modifiers: [.maskCommand])), // Cmd+Tab
                .init(input: .l1, action: .keyPress(keyCode: 115, modifiers: [])), // Page Up
                .init(input: .r1, action: .keyPress(keyCode: 119, modifiers: [])), // Page Down
                .init(input: .l3, action: .none),
                .init(input: .r3, action: .none),
                .init(input: .dpadUp, action: .none),
                .init(input: .dpadDown, action: .none),
                .init(input: .dpadLeft, action: .none),
                .init(input: .dpadRight, action: .none),
                .init(input: .ps, action: .none),
                .init(input: .share, action: .none),
                .init(input: .touchpadButton, action: .none),
                .init(input: .options, action: .exitApp)
            ]
        )
    }
}
