# ADR 索引

DS4Mate 的所有架构级别决策（Architecture Decision Records），遵循 MADR 简化格式。

| ADR | 标题 | 状态 |
|-----|------|------|
| [ADR-001](decisions/ADR-001-tech-stack.md) | Swift + SwiftUI 作为主技术栈 | Accepted · 2026-10-18 |
| [ADR-002](decisions/ADR-002-menubar-pattern.md) | MenuBarExtra(.window) + LSUIElement 实现菜单栏 App | Accepted · 2026-10-18 |
| [ADR-003](decisions/ADR-003-controller-framework.md) | 使用 GameController.framework + GCDualShockGamepad 接入 PS4 | Accepted · 2026-10-18 |
| [ADR-004](decisions/ADR-004-event-synthesis.md) | 通过 CGEvent 合成鼠标/键盘事件 | Accepted · 2026-10-18 |
| [ADR-005](decisions/ADR-005-persistence.md) | Codable JSON + Application Support 目录持久化 Profile | Accepted · 2026-10-18 |
| [ADR-006](decisions/ADR-006-project-structure.md) | Xcode Project（非 Swift Package）作为工程结构 | Accepted · 2026-10-18 |
| [ADR-007](decisions/ADR-007-testing.md) | XCTest + ViewInspector 作为测试基线 | Accepted · 2026-10-18 |

## 机器可读契约

因 DS4Mate 是**纯原生 macOS 菜单栏 App**（无 HTTP API 层），替代 OpenAPI 的机器可读契约是 Profile JSON Schema：

- [`mapping-profile.schema.json`](decisions/mapping-profile.schema.json) — `MappingProfile` 文件结构定义

任何字段变更必须**先改 Schema 再改代码**，并在 Sprint Review 中明示关联了哪些 module。

## 变更流程

1. 修改 Schema → 在 PR 中标注 schema breaking/minor
2. 编辑器（`UI/Editor/`）按 Schema 渲染表单
3. 运行时（`Engine/ActionDispatcher`）按 Schema 反序列化
4. 测试（`PersistenceTests/JSONProfileStoreTests`）goldens 与 fixtures 按 Schema 生成
