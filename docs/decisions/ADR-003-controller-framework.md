# ADR-003: 使用 GameController.framework + GCDualShockGamepad 接入 PS4 DualShock 4

## Status
Superseded · 2026-10-20（被 ADR-008 替代；最终实现改用 IOHIDManager）

## Background
PS4 DualShock 4 通过蓝牙/USB 与 Mac 通讯。Apple 在 macOS 11+ 起内置对 DualShock 4 的 profile，名为 `GCDualShockGamepad`，继承自 `GCExtendedGamepad`。

依据：Apple Docs [GCDualShockGamepad](http://docs.developer.apple.com/documentation/gamecontroller/gcdualshockgamepad) 明确：*"iOS 14.0+ ... macOS 11.0+ ... A controller profile that supports the DualShock 4 controller. The DualShock 4 controller profile is similar to an extended gamepad (GCExtendedGamepad), but has a touchpad with a button and two-finger tracking."*

实现路径：

| 选项 | API | 体积 | 工作量 | 评分 |
|------|-----|------|--------|------|
| **A. `GameController.framework` → `GCDualShockGamepad`** | Apple 一线 | 0 | ≤ 100 行 | ★★★★★ |
| B. `IOHIDManager` 读 HID 报告 | 用户态 | 0 | ≥ 500 行 | ★★ |
| C. 私有 DualShock4PID / DualSense4PID | 反向 | 0 | ≥ 1000 行 | ★ |

## Decision
**采用 A：通过 `GCController.controllers` 监听手柄出现/消失，把 `extendedGamepad as? GCDualShockGamepad` 拿到 DS4 专有 touchpad 数据，按钮/扳机/摇杆从 `GCExtendedGamepad` 父类取。**

实现要点：

- 使用 `GCController.shouldMonitorBackgroundEvents = true`（macOS 默认 false，会让 App 进后台时停收事件）
- 在 `controllerDidConnect` / `controllerDidDisconnect` 通知中更新 `AppState.availableControllers`
- 每个键的 press/release 通过 `valueChangedHandler` 闭包回传，结构化为 `RawControllerEvent` 推 `AsyncStream`
- 蓝牙重连同一手柄可能产生两个 controller 对象（见 §8 R5），按 `vendorName + serialNumber` 去重

## Consequences

**正面**
- 零代码接入；macOS 自动识别，无需 entitlements
- L2/R2 模拟值（Float 0..1）天然可读，进阶映射（"按下到 60% 触发瞄准"）直接支持
- touchpadPrimary.x/y ∈ [-1,1] 给未来手势功能留接口

**负面**
- 仅支持 macOS 11+，与公司其他用 IOHIDManager 的设备协同脚本不兼容（不存在）
- macOS 14 在某些 Bluetooth 控制器断开后延迟 1-3 秒才回调 disconnect，期间按键仍可能被旧 controller 触发
- **DS5 的高级特性（HD 震动、自适应扳机）不在 GCDualSenseGamepad 通用层暴露**，v1 不支持

**中性**
- macOS 把同一手柄广播为多个对象时要 dedup，写在中 `ControllerDiscovery`

## Alternatives Considered
- **`IOHIDManager`**：能支持 PS3 / 杂牌手柄，但工作量是 5x，且失去 L2/R2 模拟值、touchpad 等高级字段——v1 不需要
- **第三方 HIDSquirrel / GamepadKit (SwiftPM)**：引入外部依赖，对 MVP 是噪音

## Related ADRs
- ADR-001
- ADR-004（事件合成）
