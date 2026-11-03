# ADR-005: Codable JSON + Application Support 目录持久化 Profile

## Status
Accepted · 2026-10-18

## Background
DS4Mate 需要持久化的两类数据：

1. **原子偏好**：开/关、灵敏度、当前激活 profile id——简单 KV，少量
2. **Profile 对象**：包含 15 个左右 `ButtonMapping`、名称、SF Symbol、灵敏度——结构化 JSON，单文档 < 50 KB

候选方案：

| 选项 | 适用规模 | 学习成本 | 评分 |
|------|---------|---------|------|
| A. `@AppStorage / UserDefaults` | 简单 KV | 最低 | ★★★★ |
| **B. `Codable + JSONEncoder/Decoder` → 文件** | 中等结构化 | 低 | ★★★★★ |
| C. SwiftData (`@Model`) | 关系型 + 查询 | 中 | ★★★ |
| D. Core Data | 复杂迁移 | 高 | ★★ |

## Decision
**采用 A + B 混合**：

- **类别 1（原子偏好）用 `@AppStorage` + `UserDefaults`** —— 默认 `UserDefaults.standard`，keyspace：`isMappingEnabled`、`activeProfileId`、`stickSensitivity`、`scrollSensitivity`、`hasShownOnboarding`
- **类别 2（Profile 集合）用 `CodableJSONProfileStore`**，每个 Profile 一个独立 JSON 文件
  - 路径：`~/Library/Application Support/DS4Mate/profiles/{uuid}.json`
  - 备份/迁移友好：用户复制目录即可
  - ~~内置默认 Profile 放 `DS4Mate.app/Contents/Resources/DS4MateProfiles/`（只读），首次启动如果 profiles 目录空，从内置复制过去~~
  - **2026-11-03 更新**：应用不再内置任何预设。`ProfileStore.loadAll()` 在目录为空时用代码生成一份初始预设（普通预设，可改可删）；包内不再携带预设 JSON。

JSON Schema（机器可读契约）见 `mapping-profile.schema.json`。Profile 形状稳定后用 JSON Schema **锁住字段名与类型**，后续 Sprint 任何变更先改 Schema。

## Consequences

**正面**
- Profile 是值类型，`Codable` 双向 → SwiftUI 编辑器直接 `Binding`，无 ModelContext
- 单文件改动只写一份 JSON，无并发冲突（OS 文件锁）
- 备份 = tar Application Support 目录；导入 = 拷贝回目录
- 用户可直接打开 JSON 编辑（高级用户）

**负面**
- 不支持跨 Profile 的查询（"哪些按钮被映射为 mouseLeftClick"），需要查全内存列表——Profile 数量永远 < 50，无影响
- 没有版本控制字段，Profile schema 升级需要手动兼容性代码——通过在 `MappingProfile` 顶层加 `version` 字段 + decode 时的 migration 解决

**中性**
- 启动时枚举 + decode 整个 profiles 目录；性能 ≤ 10ms

## Alternatives Considered
- **SwiftData**：ModelContainer 启动 + schema migration 治理是过度工程；Profile 不需要跨实体查询
- **Core Data**：与 SwiftData 比无优势，pass
- **plist**：JSON 在版本控制 diff 友好上更胜

## Related ADRs
- ADR-001
- ADR-006
