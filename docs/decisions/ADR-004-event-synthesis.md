# ADR-004: 通过 CGEvent 合成鼠标/键盘事件

## Status
Accepted · 2026-10-18

## Background
DS4Mate 的"把手柄映射为鼠标键盘"最终是把映射后的动作合成为 macOS 输入事件。三条主要路径：

1. **`CGEvent`** (CoreGraphics) —— 系统级，跨 App 投递，最稳
2. **`Quartz Event Services`** —— 是 CGEvent 的子集命名空间，等同
3. **`XCUITest` 私有 XPC** —— 仅测试可用

依据：Apple DTS Quinn 在 2022 年 [官方答疑](https://developer.apple.com/forums/thread/707680) 明确：*"the former [NSEvent global monitor] requires the Accessibility privilege whereas the latter [CGEventTap] requires the Input Monitoring privilege."* —— 即"投出"用 Accessibility，"监听"用 Input Monitoring。

## Decision
**采用 1：`CGEvent.post(tap: .cgSessionEventTap)`**。所有动作最终由 `ActionDispatcher`（位于 `Sources/Engine/`）翻译为 CGEvent 并 post。

权限约束（按 §5 的优先级）：

| 权限 | API | 用途 |
|------|-----|------|
| Accessibility | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | 让 `CGEvent.post()` 能投递到其他 App |
| Input Monitoring | `CGPreflightListenEventAccess()` + `CGRequestListenEventAccess()` | v1 不需要监听，仅合成；检测用于"完整性检查" |

工程约束：

1. **主线程投递**：CGEvent 合成不能跨线程直接发，含 keyboard 的 modifiers 字段；统一在 `MainActor` 上 post
2. **坐标系统一**：鼠标位置使用 macOS **全显示器 union 逻辑坐标**（CGEvent 默认），不要做归一化
3. **节流**：鼠标移动由 `StickSmoother` 平滑 + 60Hz Cap
4. **失败可观测**：`PermissionManager` 持续轮询；权限缺失时 `MappingEngine.mode = .noop`，菜单栏图标变 `exclamationmark.triangle`

## Consequences

**正面**
- HID 层投递，目标 App 无法区分物理事件与合成事件
- 不依赖私有 API，不需 entitlement 调整（macOS 10.15+ 后 Input Monitoring 都开）
- 沙盒与非沙盒 App 行为一致（v1 不开沙盒为开发期方便）

**负面**
- 必须先获得 Accessibility，否则事件**静默丢弃**，没有错误码
- macOS 14 引入 Sonoma 隐私指示器菜单栏小绿/橙/紫点，仅对**录音/截屏/位置**触发；我们只合成不监听，**不会被点**
- 不能在 App 沙盒里跑（v1 接受：MVP 不上 App Store）

**中性**
- 鼠标 doubleClick 由两次 `leftMouseDown`/`leftMouseUp` 之间间隔 < 200ms 合成；用 `DispatchQueue.main.asyncAfter` 而不是 Thread.sleep

## Alternatives Considered
- **AppleScript via `NSAppleScript`**：能调菜单项但不能合成鼠标坐标事件，pass
- **`iohid` UserClient**：私有，pass

## Related ADRs
- ADR-001
- ADR-003（手柄数据源）
