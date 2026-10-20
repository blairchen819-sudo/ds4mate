# ADR-007: XCTest + ViewInspector 作为测试基线

## Status
Accepted · 2026-10-18

## Background
DS4Mate 的代码形态包含：

- 纯算法：`MappingEngine`、`StickSmoother`、`TriggerFilter` —— XCTest 单元测试覆盖
- 数据模型：`MappingProfile` 编解码 —— XCTest 覆盖
- SwiftUI 视图：`ProfileEditorView`、`MenuBarRoot` —— 需要 SwiftUI 友好测试
- 系统集成：GCController / CGEvent / Accessibility —— 无法 e2e，必须单测优先

候选测试栈：

| 组合 | 范围 | 评分 | 决定 |
|------|------|------|------|
| **A. XCTest + ViewInspector** | 全 | ★★★★★ | ✅ 选定 |
| B. 纯 XCTest | 缺 SwiftUI 友好 | ★★★ | — |
| C. XCUITest e2e | 可有 CGEvent 不可测盲区 | ★★ | 仅手工 |
| D. SnapshotTesting 截图回归 | 视觉回归 | ★★★ | v2 可选 |

## Decision
**采用 A：XCTest 单元测试 + ViewInspector SwiftUI 视图断言。**

测试分层：

| 层 | 范围 | 工具 | 覆盖目标 |
|----|------|------|---------|
| 单元 | `Engine/`, `Persistence/`, `Models/`, `Permissions/` | XCTest | ≥ 70% |
| 视图 | `UI/Editor`, `UI/Menu`, `UI/Settings` | ViewInspector + XCTestCase | 每个主视图 1 happy-path |
| 集成 | `Controller/ControllerEventStream` | XCTest fake controller | ≥ 80% |
| 手工 e2e | 真机 + 真手柄 + macOS 偏好 | 录屏 | Sprint 边界各 1 轮 |
| **回归盲区** | 鼠标物理移动 | 不可自动测 | 真机手测 |

**单测关键 hint**：

- `ActionDispatcher` 的 CGEvent post 用 in-memory sink 替换真 post（protocol 注入）
- `ControllerEventStream` 用 fake `GCDualShockGamepad`（Mock 双协议）
- `JSONProfileStore` 用临时目录

**CI（GitHub Actions 或本地 fastlane）**：

```bash
xcodebuild test -scheme DS4Mate -destination 'platform=macOS'
```

## Consequences

**正面**
- ViewInspector 提供原生 SwiftUI 断言 API，无第三方 UI 工具易变性
- 单元 + 视图覆盖 ≥ 85% 可期
- 注入 sink 让 CGEvent 单测无需触发真实输入

**负面**
- ViewInspector 跟 SwiftUI 版本绑定，Xcode 升级后偶尔需小升级 — 锁 minor version
- ViewInspector 只能测视图树不能测"用户拖动鼠标 50 px 时鼠标是否真移动"——这块手工 e2e 接管

**中性**
- **不引入** SnapshotTesting（v1）：snapshot 库会渲染差异噪音而非 bug 反馈

## Alternatives Considered
- **Appium / XCUITest**：CGEvent 输入路径在系统级，XCUITest 不便控制；pass
- **Detox for Mac**：不稳定，pass

## Related ADRs
- ADR-001
- ADR-006
