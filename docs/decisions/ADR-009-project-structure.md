# ADR-009: 采用 Swift Package（Package.swift）作为工程结构

## Status
Accepted · 2026-10-20（替代 ADR-006）

## Background
ADR-006 规划采用 Xcode project。但仓库实际以 SwiftPM 组织：`Package.swift` 定义单一 executable target `DS4Mate`；菜单栏 App 经 `swiftc` 编译后由 `scripts/build.sh` 手搓 `.app` bundle 并签名打包，无需任何 Xcode 工程文件。

## Decision
**采用 Swift Package（`Package.swift`，单一 executable target）** 作为工程结构；打包与签名由 `scripts/build.sh` 完成。

## Consequences

**正面**
- 无需 Xcode，CI 与本地统一使用 `swift` 工具链。
- 单一 executable target 直接产出菜单栏 App，结构清晰。

**负面**
- 没有 `.xcodeproj`，习惯 Xcode 的开发者需 `open Package.swift`（SwiftPM 生成的 xcworkspace）。
- 资源文件与 `Info.plist` 由 `build.sh` 手动拷贝进 `.app` bundle。

**中性**
- `Info.plist` 中 `LSUIElement=true` 仍生效（菜单栏 App 关键），由 `build.sh` 一并拷贝。

## Related ADRs
- ADR-006（已 Superseded）
