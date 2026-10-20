# ADR-001: 使用 Swift + SwiftUI 作为主技术栈

## Status
Accepted · 2026-10-18

## Background
DS4Mate 需要一个 macOS 菜单栏 App，把 PS4 手柄映射为鼠标键盘。备选生态：

- **Swift + SwiftUI** —— Apple 官方推荐；菜单栏 App 标准做法；macOS 13+ 内置 `MenuBarExtra`
- **Swift + AppKit** —— 老派稳定，但所有 UI 都要 NSViewController
- **Python (pygame + pyobjc)** —— 参考实现 [ps5-dualsense-mac-trackpad](https://github.com/ianljoun-pixel/ps5-dualsense-mac-trackpad) 的做法；优势是快速出原型，劣势是需要用户手动授权 Terminal/IDE 的 Accessibility
- **Electron** —— 跨平台但 macOS 系统级 API 暴露面差

用户硬约束："技术栈已由用户锁定：Swift + SwiftUI"

## Decision
**采用 Swift 5.9+ + SwiftUI 作为主技术栈**，辅以必要时的 AppKit 桥接（仅用于 `NSStatusItem` 不便通过 SwiftUI 直接表达的极少数场景）。

## Consequences

**正面**
- 直接调用 `GCDualShockGamepad`、`CGEvent`、Accessibility API，无需任何第三方胶水库
- 单二进制，分发简单，no extra runtime
- 可天然使用 SF Symbols，遵循 P0"禁止 emoji 作为图标"硬约束
- macOS 13+ `MenuBarExtra` 让 80% 的 UI 直接 SwiftUI 写

**负面**
- 仅 macOS，不可跨平台（用户接受）
- 学习曲线对 Python/RN 背景的开发较陡（用户接受）
- 单文件 ≤ 300 行硬约束需要主动拆分（已通过 §7 目录结构保证）

**中性**
- 测试用 XCTest，SwiftUI 视图用 ViewInspector 单独引入

## Related ADRs
- ADR-002（菜单栏实现）
- ADR-006（工程结构：Xcode project）
- ADR-007（测试框架）
