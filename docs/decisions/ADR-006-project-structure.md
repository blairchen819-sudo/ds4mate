# ADR-006: Xcode Project（非 Swift Package）作为工程结构

## Status
Accepted · 2026-10-18

## Background
DS4Mate 是一个 macOS 菜单栏 App，涉及 Info.plist、Entitlements、Assets.xcassets、Settings Scene、MenuBarExtra Scene、Test Target 等多种 Xcode 原生特性。三种工程形态：

| 选项 | 多 Scene 支持 | Info.plist 集成 | 测试集成 | 评分 |
|------|--------------|----------------|---------|------|
| **A. Xcode project (.xcodeproj)** | 原生 | 原生 | 原生 | ★★★★★ |
| B. Swift Package (SwiftPM) | 受限（App 需 .xcodeproj 包装） | 需外挂 | 需外挂 | ★★★ |
| C. Tuist / XcodeGen 工程生成 | 原生 | 原生 | 原生 | ★★★ |

用户硬约束：单文件 ≤ 300 行（架构必须考虑静态扫描硬规则）

## Decision
**采用 A：单一 Xcode project，两个 target**：

- `DS4Mate` —— App，bundle id `app.ds4mate.client`，macOS 13+
- `DS4MateTests` —— Unit Test target，XCTest，跨 target 引用 `DS4Mate` 内部类型用 `@testable import`

**目录物理结构**（详见主文档 §7）：

```
DS4Mate/                        ← project root
├── DS4Mate.xcodeproj
├── DS4Mate.entitlements        ← App Sandbox / Hardened Runtime
├── Info.plist                  ← LSUIElement + 用法说明
├── Resources/
└── Sources/
    ├── App/        ─ @main 入口
    ├── Controller/ ─ GCController 监听
    ├── Engine/     ─ 映射引擎
    ├── Models/     ─ 值类型
    ├── Persistence/
    ├── Permissions/
    ├── UI/
    └── Utilities/
DS4MateTests/                   ← 独立 test target
```

**单文件 ≤ 300 行硬约束的实现机制**：

1. 目录结构按职责拆，确保每个 .swift 文件 150-250 行平均值
2. CI 加一行 `wc -l Sources/**/*.swift | awk '$1 > 300 { exit 1 }'`
3. Models 与 Utilities 放最底层（无依赖），UI 与 App 放上层

## Consequences

**正面**
- Xcode 工程能力开箱即用，无脚手架成本
- macOS 13+ 多 Scene 原生支持，Info.plist 与 entitlements 文件标准位置
- 调试 + 模拟器 + 真机 + codesign + notarytool 全套工具链与 Xcode 集成最深
- 单文件 ≤ 300 行可在 CI 强约束

**负面**
- `.pbxproj` 文件合并冲突繁琐（团队内有冲突时手工解决）
- 不易做"跨项目复用"（如未来要做 macOS + iOS 共享 Models）

**中性**
- 单元测试必须 `@testable import DS4Mate` 才能访问 internal 类型

## Alternatives Considered
- **Swift Package Manager**：适合纯逻辑库；做菜单栏 App 要外挂 .xcodeproj 包装
- **Tuist**：预期未来工程复杂度上升时再迁移
- **XcodeGen**：同理，ci 后置引入

## Related ADRs
- ADR-001
- ADR-005（持久化目录约定）
- ADR-007（测试）
