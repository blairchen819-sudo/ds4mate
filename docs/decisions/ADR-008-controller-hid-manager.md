# ADR-008: 改用 IOHIDManager 直接读取 HID 报告接入 PS4 DualShock 4

## Status
Accepted · 2026-10-20（替代 ADR-003）

## Background
ADR-003 规划采用 `GameController.framework` 的 `GCDualShockGamepad`。但在 macOS 26 上 `GameController.framework` 存在缺陷，导致 DS4 的连接与事件回调异常，规划方案无法落地。仓库最终实现改为用 `IOHIDManager` 直接打开 DualShock 4 的 HID 设备并自行解析 HID 报告（见 `Sources/DS4Mate/Services/HIDControllerService.swift`）。

## Decision
**采用 `IOHIDManager` 直接读取 DualShock 4 的 HID 报告**，自行解析按键 / 摇杆 / 触摸板字节，不再依赖 `GameController.framework`。

## Consequences

**正面**
- 绕过 macOS 26 的 `GameController.framework` 缺陷，连接与事件稳定。
- 不依赖系统对 `GCDualShockGamepad` 的版本支持差异，跨 macOS 版本行为一致。

**负面**
- 代码量显著增大（HID 报告解析 ≥ 500 行），集中在 `HIDControllerService.swift`。
- 需自行维护按键 / 轴 / 触摸板的字节布局解析，维护成本高于框架封装。

**中性**
- 仍仅需系统蓝牙配对，无额外权限要求；事件注入仍走 `CGEvent`（ADR-004 不变）。

## Related ADRs
- ADR-003（已 Superseded）
- ADR-004（事件合成，不变）
