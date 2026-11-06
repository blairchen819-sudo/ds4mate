# DS4Mate 文档索引

本目录集中存放 DS4Mate 的**规划与设计文档**（PRD、架构、设计系统、ADR、调研）。

> ⚠️ **一致性提示**：下列文档大多写于 2026-10-18 的规划阶段（部分标注「待评审」），
> 描述的是**最初计划采用的方案**，最终代码有若干偏离。以根目录 `README.md` 与 `Sources/` 实际代码为准：
> - **PS4 接入**：文档写的是 `GameController.framework`（ADR-003 / `architecture.md` §3.1），实际代码改用 `IOHIDManager`（见 `Sources/DS4Mate/Services/HIDControllerService.swift`），原因是 macOS 26 上 GameController 的 PS4 事件流有 bug。
> - **工程形态**：`architecture.md` §K6 写「Xcode project（非 Swift Package）」，实际仓库用 SwiftPM（`Package.swift`）。
> - **千问语音控制 / 桌面切换**：这两项实际已实现（见 `QwenVoiceController.swift` / `SpaceSwitcher.swift`），但规划文档未覆盖。
> - **收敛记录（2026-10-20）**：上述分歧已通过新增 ADR-008（控制器框架改为 IOHIDManager）、ADR-009（工程结构改为 SwiftPM）并补录 PRD §4.5（附加功能）得到修正；ADR-003 与 ADR-006 标记为 Superseded。
> - **预设模型变更（2026-11-03）**：应用已删除内置的「默认 / 媒体遥控 / 演示」三套固定预设，全部预设改为用户自建；目录为空时自动生成一份初始预设。SPEC §6.5 已同步为初始预设表；PRD / architecture 中的「三套预设」表述保留为历史规划记录。
> - **触摸板认知纠正（2026-11-06）**：早期代码注释把「只收到 10 字节精简 0x01 报告」归因于 macOS 限制。实际是 Sony 固件默认档位——发一次 `GET_REPORT(feature 0x02)` 即可切到完整 0x11 报告（含触摸板）。详见 `touchpad-mouse.md` 第一节。
> - **设置窗口实现变更（2026-11-06）**：App 在 `Info.plist` 里 `LSUIElement = true`，是纯菜单栏应用、没有常规应用菜单条。SwiftUI 在这种场景下**不会**为 `Settings { }` scene 注册 `showSettingsWindow:` 的响应者，`NSApp.sendAction` 静默返回 `false` —— 表现是「点菜单栏里的设置毫无反应」。已改为 `SettingsWindowController` 自持 NSWindow + NSHostingController。`design-system/settings.md` 的布局描述仍然有效，但入口不再经过 SwiftUI 的 Settings scene，`⌘,` 在 LSUIElement 下不可用属预期。

## 文档导航

| 文件 | 内容 |
|------|------|
| `SPEC.md` | 功能规格（v1.0 锁定），按键 → 动作映射的契约 |
| `architecture.md` | 技术架构（待评审），含选型矩阵与 7 份 ADR 摘要 |
| `DESIGN.md` | UI/UX 设计（待评审） |
| `OPEN-DECISIONS.md` | 开放决策日志（5 项已全部 RESOLVED） |
| `adr-index.md` | ADR 总索引 |
| `decisions/` | 9 份 ADR（ADR-001 ~ ADR-009）+ 映射 Profile 的 JSON Schema |（ADR-003 / ADR-006 已标记 Superseded，分别被 ADR-008 / ADR-009 替代）|
| `design-system/` | 设计系统：`MASTER.md` + 6 个页面范式（menu / editor / settings / onboarding / profiles / action-picker） |
| `design-tokens.json` | W3C 标准设计 Token |
| `research/PRD-v0.1.md` | 产品需求文档（背景、竞品、目标用户、MVP 范围） |
| `touchpad-mouse.md` | 触摸板当鼠标：三个常见认知偏差的纠正、数据链路、探针验证方法、手感调参、限制与 DriverKit 迁移路径 |

## 外部参考

- 映射逻辑来源（参考实现）：[ps5-dualsense-mac-trackpad](https://github.com/ianljoun-pixel/ps5-dualsense-mac-trackpad)（MIT，Python，PS5 版）
