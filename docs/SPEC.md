# Spec — DS4Mate v1.0

> **生成日期**：2026-10-18
> **基于**：PRD v0.1 + 架构文档 v1.0 + UI/UX 设计 v1.0
> **状态**：已锁定 · 等同于团队契约
> **OPEN-DECISIONS**：0 未决 / 5 已决（见 `docs/OPEN-DECISIONS.md`）

---

## 1. 产品定义

- **一句话描述**：把 PS4 DualShock 4 手柄变成 Mac 的指针/键盘遥控器，原生 SwiftUI 菜单栏 App，可视化改键。
- **目标用户**：macOS 重度玩家 + 手柄爱好者（Eric 型用户），想躺在沙发上遥控 Mac；次要用户为 a11y 需求用户、客厅 HTPC 用户。
- **核心问题**：现存方案要么是 Python 脚本 + 终端（`ps5-dualsense-mac-trackpad`），要么是停更多年的 OSS（Enjoyable），要么是闭源付费商业软件（ControllerMate / BetterTouchTool）。需要一个**原生 + 开源 + 可视化编辑 + 菜单栏常驻**的中间解。

---

## 2. MVP 范围（锁定——不在此列表的功能一律不做）

| 优先级 | 功能 | 验收标准摘要 | RICE 评分 |
|--------|------|-------------|-----------|
| P0 | F1 蓝牙自动连接 + 自动重连 PS4 DualShock 4 | AC-1, AC-2 | 10.0 |
| P0 | F2 菜单栏图标 + 启停总开关 + 连接状态指示 | 主菜单下拉展开 < 100ms | 20.0 |
| P0 | F3 默认可用映射（默认/媒体/演示 三套） | AC-4, AC-6 | 15.0 |
| P0 | F4 可视化键位编辑器（按 PS4 按键 → 动作选择器） | AC-5 | 4.8 |
| P0 | F5 三套预设：默认 / 媒体遥控 / 演示 | AC-6 | 10.0 |
| P0 | F6 Accessibility 权限引导（首启动 + 缺失检测 + 1.5s 轮询） | AC-8, AC-9 | 20.0 |
| P1 | F7 断开检测 + 自动暂停（防误触卡键） | AC-3 | 6.4 |
| P1 | F8 死区 / 灵敏度 / 响应曲线调节 | 边界条件 | 1.87 |
| P1 | F9 摇杆反向、按键互换 | — | 3.0 |
| P1 | F10 配置导入导出（JSON） | — | 5.0 |
| P2 | F11 多 Profile（v1.2） | — | 1.0 |
| P2 | F12 Xbox/PS5/Switch 手柄支持 | — | 0.5 |

---

## 3. 明确不做（Out-of-Scope — 锁定）

| 不做的功能 | 原因 | 何时考虑 |
|------------|------|----------|
| Xbox One / PS5 DualSense / Switch Pro 手柄支持 | v1 范围聚焦 PS4；多协议驱动开发量翻倍 | v2.0 |
| USB 有线连接 | 蓝牙是目标场景；USB DS4 走非标准 HID 协议 | v2.0（若用户反馈成立） |
| 触摸板手势映射（多指） | v1 仅消费 `touchpadButton` 与 `touchpadPrimary.x/y` 单点 | v1.1 视需求评估 |
| 宏录制 / JavaScript 脚本引擎 | 与"开箱即用 + 单一职责"原则冲突 | 不考虑 |
| 云同步 / 账号体系 | 隐私优先 + Eric 不愿引入 | 不考虑 |
| App Store 发布 | 沙盒与 CGEvent 历史冲突 | 不考虑 |
| App 内自动更新 | 隐私 + Eric 偏好手动升级 | 不考虑 |
| 电量百分比提示（AC-10） | 需要走 IOHIDManager 私有路径；架构师未给出稳定方案 | v1.1 若方案稳定 |
| 自定义 LED 颜色 / 震动 | 走 HID 报告，与 GameController 框架不兼容 | 不考虑 |
| 多手柄并发 | 复杂度高，单手柄覆盖 95% 场景 | v2.0 |

---

## 4. 技术架构（锁定 — 含版本锚定）

> **规则**：所有"如何实现"的问题均已锁定，开发期间不允许私下换技术栈。任何变更必须先开 ADR。

| 层 | 技术 | 实际版本 | 锁定原因 |
|----|------|----------|----------|
| 开发语言 | Swift | 5.9+ (Xcode 15) | 用户硬约束 |
| UI 框架 | SwiftUI | iOS 16 / macOS 13 SDK | 用户硬约束 |
| 进程入口 | `@main App` + `MenuBarExtra` Scene | macOS 13+ | 架构 §4.1 |
| 菜单栏 | `MenuBarExtra(.window)` | macOS 13+ | 架构 §4.2；`.window` 风格承载可视化编辑器 |
| Dock 隐藏 | `Info.plist: LSUIElement = true` | — | 架构 §3.2 双重保险 |
| PS4 接入 | `GameController.framework` → `GCDualShockGamepad` | macOS 11+ | 架构 §3.1 零代码接入 |
| 事件合成 | `CoreGraphics.CGEvent.post(tap: .cgSessionEventTap)` | macOS 全版本 | 架构 §3.3 系统级输入唯一稳态 |
| 权限检测 | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | macOS 全版本 | 架构 §3.4 |
| 配置持久化（偏好） | `@AppStorage`（UserDefaults 包装） | — | 架构 §4.5 |
| 配置持久化（Profile） | `Codable` + `JSONEncoder/Decoder` → `~/Library/Application Support/DS4Mate/profiles/{name}.json` | — | 架构 §4.5 |
| Schema 契约 | `mapping-profile.schema.json`（JSON Schema Draft 2020-12） | — | 见 §5 |
| 工程结构 | Xcode project（双 target：App + Tests） | Xcode 15+ | 架构 §4.6 |
| 图标库 | **SF Symbols 5**（`gamecontroller.fill` 等） | macOS 13+ 资源 | 设计 §A + 架构 ADR |
| 测试 | XCTest 单元 + ViewInspector 视图 | — | 架构 ADR-007 |
| 打包 | `xcodebuild` + `xcrun productbuild` 输出 `.pkg`；通过 Homebrew Cask + GitHub Release 分发 | — | 架构 §11 |
| macOS 最低版本 | macOS 13 Ventura | — | 架构 §1.2 + 团队共识 |
| macOS 推荐版本 | macOS 14 Sonoma（用 `MenuBarExtra` 全部能力） | — | 架构 §1.2 |

### ADR 索引（详细选型理由）
- ADR-001 技术栈（Swift + SwiftUI 锁定）
- ADR-002 菜单栏模式（MenuBarExtra + LSUIElement）
- ADR-003 PS4 接入（GameController vs IOHID）
- ADR-004 事件合成（CGEvent）
- ADR-005 持久化（@AppStorage + Codable JSON）
- ADR-006 工程结构（Xcode 双 target）
- ADR-007 测试（XCTest + ViewInspector）

---

## 5. 接口契约（锁定——开发时以此为唯一依据）

> 本项目是本地 macOS App，**没有 HTTP 层**。"接口契约"由三部分构成：Profile JSON Schema、系统集成点、文件路径。

### 5.1 Profile JSON Schema
完整 Schema：`docs/decisions/mapping-profile.schema.json`（JSON Schema Draft 2020-12）。前端/后端/QA 共用此 Schema 验证导入导出与破坏性变更。

```yaml
Profile:
  id: UUID
  name: string  # "默认" / "媒体遥控" / "演示" / 自定义
  version: 1
  isBuiltin: bool
  bindings:
    - { input: ButtonInput, action: Action }
  parameters: { deadzone, sensitivity, scrollSpeed, ... }

ButtonInput: enum  # 见 §6
Action: enum        # 见 §6
```

### 5.2 系统集成点（开发时必须严格按以下入口调用）

| 集成 | 入口 | 备注 |
|------|------|------|
| 蓝牙连接 | `GCController.controllers` + `GCControllerDidConnect` NotificationCenter | 系统原生 |
| DS4 特定数据 | `controller.extendedGamepad as? GCDualShockGamepad` | 拿到 touchpad/motion |
| 鼠标移动 | `CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)` | 必须 `post(tap: .cgSessionEventTap)` |
| 鼠标左键按下/抬起 | `CGEvent` `mouseType: .leftMouseDown / .leftMouseUp` | — |
| 鼠标右键/中键 | 同上，换 mouseType | — |
| 滚轮 | `CGEvent` `scrollWheelEvent` + `setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: dy)` | 像素量，非行数 |
| 键盘 | `CGEvent(keyboardEventSource: nil, virtualKey: kVK_* , keyDown: true/false)` | kVK 取自 Carbon HIToolbox/Events.h |
| 修饰键 | `CGEventFlags` 拼接 | — |
| 媒体键 | NSEvent.monitor + NSPostEvent；或 `NX_KEYTYPE_*` 私有路径（v1 不做） | v1 不支持 |
| 截图 | `screencapture` 命令 | — |
| 调度中心 | `AXSystemWideAction` (私有，v1 不做) → 用 `Cmd+F3` 替代 | v1 用键盘快捷键 |
| 显示桌面 | `F11` | — |
| Launchpad | 触发 Spotlight 模拟或 `Cmd+Space` 后输入 | v1 用 `Cmd+Space` |

### 5.3 文件路径

| 资源 | 路径 |
|------|------|
| Profile 目录 | `~/Library/Application Support/DS4Mate/profiles/` |
| 默认 Profile | 同目录下 `default.json` / `media.json` / `presentation.json`（isBuiltin=true 不可删） |
| 用户自定义 Profile | `~/Library/Application Support/DS4Mate/profiles/{uuid}.json` |
| 应用偏好 | `~/Library/Preferences/com.ds4mate.app.plist`（@AppStorage 走 UserDefaults） |
| 日志 | `~/Library/Logs/DS4Mate/{date}.log`（v1.1 候选，v1 可走 os_log） |

### 5.4 Bundle Identifier
- 主 App：`com.ds4mate.app`
- Test Bundle：`com.ds4mate.app.tests`

---

## 6. 数据模型（锁定）

```swift
// 6.1 PS4 DualShock 4 输入面（按物理按键枚举）
enum ControllerInput: String, Codable, CaseIterable {
    // 数字按键（继承 GCExtendedGamepad）
    case cross        // ×
    case circle       // ○
    case square       // □
    case triangle     // △
    case l1
    case r1
    case l2Trigger    // 模拟值 Float 0...1
    case r2Trigger    // 模拟值 Float 0...1
    case l3           // 左摇杆按下
    case r3           // 右摇杆按下
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case share
    case options
    case ps
    case touchpadButton
    
    // 模拟轴（连续值，需死区处理）
    case leftStickX, leftStickY        // 左摇杆 2D
    case rightStickX, rightStickY      // 右摇杆 2D
    case leftTriggerAxis               // L2 模拟
    case rightTriggerAxis              // R2 模拟
}

// 6.2 动作枚举（用户可在编辑器中选择的目标动作）
enum Action: Codable, Hashable {
    // 鼠标动作
    case mouseLeftClick
    case mouseRightClick
    case mouseMiddleClick
    case mouseDoubleClick
    case mouseDragToggle            // L3 切换拖拽模式
    case mouseMoveCursor           // 摇杆 → 鼠标移动（持续）
    case scroll                    // 摇杆 → 滚轮（持续）
    case fineScroll                // 扳机 → 精细滚轮（连续）
    
    // 键盘动作
    case keyPress(virtualKey: Int, modifiers: CGEventFlags)
    case keyChord(keys: [Int], modifiers: CGEventFlags)
    case typeString(String)        // v1.1 候选
    
    // 系统快捷键（v1 用预定义组合）
    case systemShortcut(preset: SystemShortcut)
    
    // 媒体键（v1 不支持 macOS 媒体键，改为键盘模拟）
    case mediaKey(MediaAction)     // v1.1 候选
    
    // 元动作
    case none                      // 禁用该按键
    case exitApp                   // Options 默认绑定
    case toggleAppEnabled          // 总开关切换
    case cycleProfile              // 循环切换预设
    case openMainWindow            // 打开主窗口
}

enum SystemShortcut: String, Codable, CaseIterable {
    case showDesktop = "F11"
    case missionControl = "Cmd+F3"
    case appExpose = "Ctrl+F4"
    case launchpad = "Cmd+Space"
    case screenshotFull = "Cmd+Shift+3"
    case screenshotSelection = "Cmd+Shift+4"
    case lockScreen = "Cmd+Ctrl+Q"
    case browserBack = "Cmd+["
    case browserForward = "Cmd+]"
}

enum MediaAction: String, Codable {
    case playPause, next, previous, volumeUp, volumeDown, mute
}

// 6.3 Profile（核心持久化对象）
struct Profile: Codable, Identifiable {
    let id: UUID
    var name: String
    var version: Int = 1
    var isBuiltin: Bool
    var bindings: [Binding]
    var parameters: ProfileParameters
}

struct Binding: Codable, Hashable {
    let input: ControllerInput
    var action: Action
}

struct ProfileParameters: Codable {
    var deadzone: Double = 0.05          // 0.0–0.30
    var cursorSensitivity: Double = 1.0  // 0.1–3.0
    var scrollSensitivity: Double = 1.0
    var fineScrollSensitivity: Double = 0.3
    var invertLeftStickX: Bool = false
    var invertLeftStickY: Bool = false
    var invertRightStickX: Bool = false
    var invertRightStickY: Bool = false
    var buttonSwapXY: Bool = false        // ×↔○ / □↔△
}

// 6.4 应用运行时状态（不持久化 / @AppStorage）
struct AppRuntimeState: Codable {
    var activeProfileID: UUID
    var isMappingEnabled: Bool = true
    var hasCompletedOnboarding: Bool = false
    var lastPermissionCheck: Date = .distantPast
}
```

### 6.5 默认三套 Profile 绑定表（锁定）

| DS4 按键 | 默认 Preset | 媒体 Preset | 演示 Preset |
|----------|-------------|-------------|-------------|
| leftStickX/Y | scroll（持续） | none | dpadKeys |
| rightStickX/Y | mouseMoveCursor | volumeUpDown | mouseMoveCursor |
| leftTriggerAxis | fineScroll | volumeDown | pageUp |
| rightTriggerAxis | fineScroll | volumeUp | pageDown |
| cross | mouseLeftClick | playPause | nextSlide |
| circle | mouseRightClick | stop | escape |
| square | mouseMiddleClick | previous | hideWindow |
| triangle | mouseDoubleClick | next | switchApp |
| l1 | browserBack | previous | pageUp |
| r1 | browserForward | next | pageDown |
| l3 | mouseDragToggle | none | none |
| r3 | openLaunchpad | none | none |
| dpadUp | missionControl | none | none |
| dpadDown | appExpose | none | none |
| dpadLeft | browserBack | previous | none |
| dpadRight | browserForward | next | none |
| **ps** | **none（禁用，RESOLVED 2026-10-18）** | none | none |
| share | screenshotSelection | none | none |
| touchpadButton | missionControl | mute | none |
| options | exitApp | exitApp | exitApp |

---

## 7. 页面清单（锁定）

| 页面 | 类型 | 路由/入口 | 核心组件 | 对应 API | 设计 Token 主题 |
|------|------|-----------|----------|----------|-----------------|
| 主菜单 | MenuBarExtra 下拉 | 点击菜单栏图标 | 状态行、Profile 切换、启停开关、打开主窗口、设置、关于、退出 | — | Steel Blue 500 |
| 键位编辑器（主窗口） | WindowGroup（从菜单打开） | 菜单"打开主窗口" | 手柄 SVG 可视化、按键详情面板、动作选择器、Profile 切换 | — | Steel Blue 600 |
| 动作选择器 | Sheet（从编辑器触发） | 点击任一按键 | 搜索框、分类 Tab、动作卡片网格、属性面板 | — | Steel Blue 500 |
| 预设管理 | Window | 菜单"管理预设" | 3 卡片网格 + "+ 新建" | — | Steel Blue 500 |
| 设置 | Settings Scene | 菜单"设置…" | 通用、菜单栏图标、权限状态、危险区（重置/卸载） | — | Steel Blue 500 |
| 关于 | Settings Scene | 菜单"关于" | 版本、源码链接、贡献者、许可 | — | Steel Blue 500 |
| Onboarding（首启动 4 步） | Sheet 自动 | 首次启动 | 欢迎 / 权限 / 配对 / 试玩 | — | Steel Blue 600 |

---

## 8. 设计 Token（锁定）

> 完整 Token 见 `docs/design-tokens.json`（W3C Design Token 标准格式）。
> 设计师已同时产出 `design-tokens.css` 供前端 import；`design-tokens.json` 作为机器可读源。

| 维度 | 取值 | 备注 |
|------|------|------|
| 主色 | **Steel Blue 600 = `#1E5BAF`** | 设计 P0 自检：避开紫粉 + 呼 PS4 品牌 + 对比度 11.2:1 |
| 备选主色 | Graphite Teal `#0F766E` / Steel `#475569` | 设计师备选 |
| 字体 | SF Pro + Noto Sans SC | 拉丁 + 中文双栈 |
| 主题 | 浅色 + 深色双套 | 跟随 macOS 系统设置 |
| 对标品牌 | Steam Controller / Stream Deck | 编辑器范式参考 |
| 图标库 | **SF Symbols 5**（macOS 原生矢量） | 锁定，0 成本 |
| 图标尺寸 | 16px（行内）/ 20px（按钮内）/ 24px（独立） | 全项目一致 |
| 圆角 | sm 6 / md 8 / lg 12 | 8 的倍数 |
| 间距 | 4px 基础，1–12 倍数 | — |
| 动画 | fast 150ms / normal 250ms / slow 400ms | cubic-bezier(0.4, 0, 0.2, 1) 标准 |

---

## 9. 验收标准（锁定——QA 测试时以此为唯一依据）

> EARS 格式：While/When/If/Where + 系统 + 必须/应该 + 行为。

| 编号 | 功能 | EARS 验收标准 | 优先级 |
|------|------|---------------|--------|
| AC-1 | F1 蓝牙连接 | **When** DualShock 4 通过 macOS 蓝牙设置配对，**Then** 菜单栏图标 5 秒内从"未连接"变"已连接"，**And** 按 × 触发鼠标左键 | P0 |
| AC-2 | F1 自动重连 | **When** DualShock 4 关机 30 秒后再开机，**Then** App 自动建立连接，无需用户操作 | P0 |
| AC-3 | F7 断开保护 | **When** 手柄连接丢失，**Then** 3 秒内自动暂停事件注入，**And** 菜单栏显"已断开"，**And** 不留卡键导致的虚假连续输入 | P0 |
| AC-4 | F3 默认映射 | **Where** "默认 Preset" 激活且手柄已连接，**Then** §6.5 默认映射表逐条生效 | P0 |
| AC-5 | F4 编辑器 | **When** 用户点击 × 键并选新动作"音量减小"，**Then** ≤1 秒内生效，**And** 持久化到 Profile JSON | P0 |
| AC-6 | F5 预设切换 | **When** 菜单栏选"媒体遥控"，**Then** 所有按键映射立刻切换，**And** 不抢焦点、不发意外按键 | P0 |
| AC-7 | 退出 App | **When** 菜单栏"退出 DS4Mate"或按 Options 1 秒，**Then** 完全停止事件注入并退出，**And** 无后台进程残留 | P0 |
| AC-8 | F6 权限引导 | **While** 首启动且未授权 Accessibility，**Then** 主窗口顶部显示引导条，**And** 点击跳转系统设置并高亮 DS4Mate.app，**And** 未授权时禁用事件注入 | P0 |
| AC-9 | F6 静默恢复 | **When** 用户在系统设置中授权后切回 App，**Then** ≤3 秒内检测到并启用事件注入 | P0 |
| AC-10 | 性能 | **Where** 启用映射，**Then** 事件注入延迟 < 16ms（60Hz）；菜单栏下拉 < 100ms；编辑器按键展开 < 150ms | P0 |
| AC-11 | 数据完整性 | **Where** 修改 Profile 后退出 App，**Then** 下次启动时修改完整恢复；Profile JSON 符合 `mapping-profile.schema.json` | P0 |
| AC-12 | 单手柄 | **When** 检测到第二只 DualShock，**Then** 提示用户断开第一只（不自动切换） | P0 |
| AC-13 | 系统安全 | **Where** App 运行中，**Then** 无网络请求；不读取用户文件（除 Profile 目录外）；不调用私有 API | P0 |
| AC-14 | macOS 兼容 | **Where** macOS 13.0 / 14.0 / 15.0 任一版本，**Then** App 启动、菜单栏显示、事件注入均工作正常 | P0 |

---

## 10. 边界与约束

- **macOS 最低版本**：macOS 13 Ventura（架构师硬约束）
- **架构支持**：Apple Silicon 优先；Intel Mac 兼容（架构师评估 CGEvent 性能）
- **不响应区域**：锁屏界面、登录界面、休眠期间不注入事件
- **资源占用**：常驻内存 < 50MB；CPU 空闲 < 0.5%
- **崩溃容忍**：单 Profile JSON 损坏不影响其他 Profile 加载；损坏文件自动备份为 `*.broken.{timestamp}.json`
- **配置文件原子写入**：通过 `Data.write(to:options: .atomic)` 防止半写损坏
- **不做 A11y 高级特性**：VoiceOver 标签可读，但不承诺完整 a11y 合规（v1 之后改进）
- **国际化**：v1 仅简体中文；string catalog 化（`Localizable.strings`）便于后续扩展
- **日志**：v1 走 `os_log`（系统统一收集）；自定义日志文件推迟 v1.1
- **崩溃报告**：v1 不集成第三方 SDK（无 Sentry/Crashlytics）

---

## 11. 内嵌已知坑（从项目记忆拉取）

> 启动 Phase 3 开发时，前端/后端 spawn prompt 会召回此清单，防止重蹈覆辙。
> 当前 v1 启动时为空（新项目）。开发过程中遇坑会增量追加。

| 坑 | 技术栈指纹 | 根因 | 修法 |
|----|------------|------|------|
| （暂无） | — | — | — |

---

## 12. 端到端验证步骤（Spec 锁定的最后一项）

> QA 验证 + 用户验收测试都按此步骤跑。

### 12.1 准备

```bash
# 1. 拉取源码
git clone https://github.com/ericmr/ds4mate.git
cd ds4mate

# 2. 用 Xcode 15 打开
open DS4Mate.xcodeproj

# 3. 配置签名
# Xcode -> DS4Mate target -> Signing & Capabilities
# Team: <your Apple ID team>, Bundle ID: com.ds4mate.app

# 4. 构建 + 运行
xcodebuild -scheme DS4Mate -destination 'platform=macOS' build
xcodebuild -scheme DS4Mate -destination 'platform=macOS' test  # 跑单元 + 视图测试
```

### 12.2 核心成功流（用户视角）

```bash
# 1. 启动 App
open build/Release/DS4Mate.app

# 2. 预期：菜单栏出现 gamecontroller.fill 图标，弹出 4 步 Onboarding
# 3. 配对 PS4 手柄：按住 Share + PS 直到灯快闪
# 4. macOS 蓝牙设置中接受配对请求
# 5. 预期：5 秒内菜单栏图标变 active 状态（深色）
# 6. 按 × 键：预期鼠标光标位置触发左键点击
# 7. 推动右摇杆：预期鼠标光标移动
# 8. 点击菜单栏 -> 打开主窗口
# 9. 在编辑器中点击 × 键 -> 在动作选择器选"音量减小"
# 10. 预期：保存后按 × 触发音量减小（系统音量 UI 出现）
# 11. 菜单栏 -> 切换到"媒体遥控"预设
# 12. 预期：所有按键映射立即切换
# 13. 按 Options 1 秒
# 14. 预期：App 完全退出，无 Dock 残影
```

### 12.3 关键错误流

```bash
# 场景 A：拒绝 Accessibility
# 1. 启动 App
# 2. 在 Onboarding 第 2 步拒绝授权
# 3. 预期：引导条持续显示，事件注入禁用，按 × 不触发点击
# 4. 去系统设置手动授权
# 5. 回到 App
# 6. 预期：≤3 秒内事件注入启用

# 场景 B：手柄断开
# 1. 启动 App，连接手柄，按 × 验证可用
# 2. 长按 PS 直至手柄关机
# 3. 预期：3 秒内菜单栏显"已断开"，按 × 不再触发
# 4. 重新长按 PS 开机
# 5. 预期：5 秒内重新连接，按 × 再次可用

# 场景 C：Profile 损坏
# 1. 手动编辑 ~/Library/Application Support/DS4Mate/profiles/default.json
#    注入非法 JSON
# 2. 重启 App
# 3. 预期：损坏文件备份为 *.broken.{timestamp}.json，加载内置默认 Profile
# 4. 预期：其他 Profile 正常加载
```

### 12.4 自动化测试

```bash
# 单元测试（数据模型、Profile 编解码、Action 解析）
xcodebuild test -scheme DS4Mate -only-testing:DS4MateTests/UnitTests

# 视图测试（ViewInspector 覆盖编辑器、动作选择器、菜单栏下拉）
xcodebuild test -scheme DS4Mate -only-testing:DS4MateTests/ViewTests

# E2E 需手柄实机
```

---

## 13. 变更记录

| 日期 | 变更内容 | 原因 | 影响范围 |
|------|----------|------|----------|
| 2026-10-18 | 初版 Spec 生成 | Phase 1 三文档拍板 + 用户对 R-5 选 A | 全局 |

---

**文档结束。开发期间所有"是否做 X"的疑问 → 先翻本 Spec。如果 Spec 没有 → 走变更流程（影响小：更新本表；影响大：回到 Phase 0 重新走需求澄清）。**
