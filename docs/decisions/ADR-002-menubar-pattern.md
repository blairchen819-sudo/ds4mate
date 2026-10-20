# ADR-002: MenuBarExtra(.window) + LSUIElement 实现菜单栏 App

## Status
Accepted · 2026-10-18

## Background
DS4Mate 的运行形态是**菜单栏 App**：不显示 Dock 图标、不进 ⌘Tab 切换器、关窗时进程继续运行。需要在 macOS 13 / 14 之间都稳定，并且能承载 SwiftUI 自定义可视化键位编辑器。

三种实现路径：

1. **SwiftUI `MenuBarExtra(.window)`** + `LSUIElement=true` Info.plist
2. **`NSStatusItem` + `NSPopover`（纯 AppKit）**
3. **`MenuBarExtra(.menu)`**（仅原生 NSMenu）

依据：Apple Docs [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) 明文 *"a common behavior is for the app to not display its icon in either the Dock or the application switcher. To enable this behavior, set the LSUIElement flag in your app's Information Property List file to true."*

## Decision
**采用 1：菜单栏唯一场景用 `MenuBarExtra(.window)`**，Info.plist 写 `LSUIElement = true`，构建产物 `info.plist` 必备三条：

- `LSUIElement = true` —— 隐藏 Dock 图标
- `NSAppleEventsUsageDescription = "DS4Mate uses AppleEvents to launch system commands mapped from your controller."` —— 未来 hotkey 调 app 用
- `LSMinimumSystemVersion = 13.0`

设置窗口用 `Settings` Scene（macOS 13+ SwiftUI 原生支持）+ macOS 14 用 `SettingsLink` 在菜单栏里挂入口。

## Consequences

**正面**
- 单一 Scene 概念，避免 AppKit + SwiftUI 双生命周期打架
- 状态通过 `@Observable AppState` 注入，SwiftUI 自动响应手柄连接态变化
- `.window` 风格直接承载可视化编辑器（Canvas + Form），无需写 NSPopover 自定义 host
- 用户移除菜单栏图标时，App 自动终止（系统行为，正是菜单栏 App 期望）

**负面**
- `.window` 风格窗体宽度受菜单栏宽度约束——可视区域有限，编辑器要分页或分 Tab
- 如果用户移除菜单栏图标（macOS 13+ 支持），App 退出；首次发布 README 必须说清
- 旧版 macOS（12-）无 MenuBarExtra，**最低 macOS 必须 13**

**中性**
- 双击菜单栏图标进 Settings 默认行为须主动阻止（NSApp.activate 配合 openSettings）

## Alternatives Considered
- **`NSStatusItem + NSPopover`**：被排除是因为需 5x 以上的 SwiftUI-AppKit 双向状态桥接代码，超出 MVP 范围
- **`MenuBarExtra(.menu)`**：被排除是因为可视化键位编辑器（Canvas + Form + Slider）无法在 NSMenu 上表达

## Related ADRs
- ADR-001（技术栈）
- ADR-006（工程结构）
