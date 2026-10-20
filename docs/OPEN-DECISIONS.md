# Open Decisions Log — DS4Mate

> 格式：MADR + 状态机（OPEN → RESOLVED）。
> 每次 Phase 开始时把未决项自动复现到工作上下文最前面（带「N 未决 + M 已决」汇总）。

| Date | Source | Open Item | Related Constraints | Current Leaning | Blocked By | Resolves When | Status |
|------|--------|-----------|---------------------|-----------------|------------|---------------|--------|
| 2026-10-18 | PRD §9 R-1 | 蓝牙栈选型 GameController vs IOHID | v1 不做触摸板手势、不做 LED/震动自定义 | GameController | — | 架构师已选 GameController（架构 §3.1、ADR-003） | **RESOLVED** · Resolution: GameController + GCDualShockGamepad |
| 2026-10-18 | PRD §9 R-2 | Accessibility 权限失效时降级 vs 拒绝运行 | 安全优先、最透明 | 拒绝运行直到重新授权 | — | 架构师已选「直接拒绝运行」（架构 §5.3） | **RESOLVED** · Resolution: 直接拒绝运行 |
| 2026-10-18 | PRD §9 R-3 | App Store vs 直分发 | 沙盒与事件注入历史冲突 | Homebrew Cask + GitHub Release | — | 架构师已选「直分发」（架构 §11） | **RESOLVED** · Resolution: Homebrew Cask + GitHub Release |
| 2026-10-18 | PRD §9 R-4 | 菜单栏 NSStatusItem vs MenuBarExtra | macOS 13+ 已锁定 | MenuBarExtra(.window) | — | 架构师已选 MenuBarExtra（架构 §4.2、ADR-002） | **RESOLVED** · Resolution: MenuBarExtra(.window) + LSUIElement=true |
| 2026-10-18 | PRD §9 R-5 | 默认 Preset 中 PS 键映射 | 误触风险 | 用户拍板 | — | 用户 2026-10-18 23:58 选 A | **RESOLVED** · Resolution: **A — 默认禁用**（避免误触破坏桌面；文档提示"PS 键可在编辑器内重新分配"） |

## 汇总
- **未决：0**
- **已决：5**
