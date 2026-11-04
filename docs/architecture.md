# DS4Mate 技术架构文档

> **版本**: v1.0 草案 · **状态**: 待 PM 评审 · **作者**: 高见远（首席架构师） · **日期**: 2026-10-18
> **关联**: PRD（由 PM 产出）、参考实现 [ps5-dualsense-mac-trackpad](https://github.com/ianljoun-pixel/ps5-dualsense-mac-trackpad)
> **目标平台**: macOS 13 Ventura（最低）/ macOS 14 Sonoma（推荐）
> **开发语言**: Swift 5.9+ · SwiftUI · Xcode 15+

---

## 0. 阅读路径

本文档面向 PM / 设计 / 开发三类角色。如果你只想看结论，跳到 §2 与 §9。如果你需要做技术选型复核，按需读 §3（联网调研结论）、§4（选型矩阵）、§8（风险）。开发同学在动手前请同步阅读 §5（权限）、§6（数据模型）、§7（文件结构）与附录 C（7 份 ADR）。

---

## 1. 项目目标与硬约束

### 1.1 目标

把 PS4 DualShock 4 手柄变成 macOS 上的指针/键盘输入设备，并通过菜单栏 App 提供**可视化键位编辑**，让用户**自定义每个按键 → 鼠标/键盘动作**的映射。

### 1.2 来自用户/PM 的硬约束（不可改）

- 技术栈：**Swift + SwiftUI**，不接受 Python、Electron、Tauri 替代
- 仅 macOS，**目标版本 macOS 13+（最低）/ 14+（推荐）**
- **菜单栏 App**：不显示 Dock 图标，不出现在 ⌘Tab 切换器
- 单文件 ≤ 300 行（架构设计必须支持后续基于此做静态扫描）
- 图标系统：必须使用 **SF Symbols**（macOS 系统矢量图标库，全项目统一）
- 文案/方案禁止 AI 模板味、紫粉渐变

### 1.3 非目标（v1 不做）

- 触控板手势映射（v1 仅消费 `touchpadButton`、`touchpadPrimary.x/y`，不做多指手势）
- DS5 DualSense 专用功能（自适应扳机、HD 震动）
- 远程串流 / 云同步
- 自定义脚本引擎（v1 仅支持预定义动作枚举）

---

## 2. 关键决策摘要（TL;DR）

| # | 决策 | 取值 | 一句话理由 |
|---|------|------|------------|
| K1 | 进程入口 | SwiftUI `@main App` + 单 `MenuBarExtra` Scene | macOS 13+ 标准做法，少量桥接 AppKit |
| K2 | 菜单栏实现 | **`MenuBarExtra(.window 风格)`** + `LSUIElement=true` | Apple 官方推荐；`.window` 风格承载可视化编辑器 |
| K3 | PS4 接入层 | **IOHIDManager 直接读 HID 报告**（绕过 macOS 26 的 GameController.framework 缺陷） | 连接稳定，不依赖系统对 `GCDualShockGamepad` 的支持 | 见 ADR-008 |
| K4 | 事件合成 | **CoreGraphics CGEvent**（`post(tap: .cgSessionEventTap)`） | 系统级输入唯一稳态路径，Quartz Event Services 是同一 API 另一入口 |
| K5 | 持久化 | **Codable JSON** 文件，存放于 `Application Support/DS4Mate/profiles/*.json` | Profile 是普通对象图，不需要查询、不需要 SwiftData 复杂度 |
| K6 | 工程结构 | **Swift Package（Package.swift，单一 executable target）** | 无需 Xcode，统一 swift 工具链；打包/签名由 scripts/build.sh 完成 | 见 ADR-009 |
| K7 | 测试框架 | **XCTest 单元测试 + ViewInspector SwiftUI 视图测试** | 都是 Apple 一线选择；不引入第三方 E2E |

详见 §4 选型矩阵 + 附录 C 的 7 份 ADR。

---

## 3. 联网技术调研结论（5 个核心问题的官方文档答案）

> 调研方法：直接读 Apple Developer Documentation（developer.apple.com）、Quinn "The Eskimo" DTS 在 Apple Developer Forums 的官方答疑、以及开源实现 ps5-dualsense-mac-trackpad（pygame + CoreGraphics）作行为对照。

### 3.1 Q1 — PS4 DualShock 4 在 macOS 上被原生识别吗？

> ⚠️ **规划与实现不一致**：本节为规划期调研结论，描述的是 `GameController.framework` 路线。最终实现因 macOS 26 的 GameController.framework 缺陷改用 `IOHIDManager` 直接读取 HID 报告（见 [ADR-008](decisions/ADR-008-controller-hid-manager.md)）。本节保留作调研记录。

**结论：是的，零代码接入。** macOS 11+ 内置 `GCDualShockGamepad`（继承自 `GCExtendedGamepad`）。只要手柄通过蓝牙或 USB 与 Mac 配对，`GCController.controllers` 列表里就会出现，`controller.extendedGamepad as? GCDualShockGamepad` 即可拿到 DS4 专属 touchpad 数据。

**关键证据**：Apple Docs [GCDualShockGamepad](http://docs.developer.apple.com/documentation/gamecontroller/gcdualshockgamepad) 明确写出 *"iOS 14.0+ ... macOS 11.0+ ... A controller profile that supports the DualShock 4 controller"*。特性包括：
- `touchpadButton: GCControllerButtonInput!` — 触控板按压
- `touchpadPrimary / touchpadSecondary: GCControllerDirectionPad!` — 双指坐标 (x,y ∈ [-1,1])
- `motion: GCMotion?` — 三轴加速度 + 三轴陀螺仪
- 父类 `GCExtendedGamepad` 提供：`buttonA/B/X/Y`、`leftShoulder(L1)/rightShoulder(R1)`、`leftTrigger(L2)/rightTrigger(R2)`（均为 Float，0...1，**模拟值**）、`leftThumbstick/rightThumbstick`（xAxis/yAxis，Float，-1...1）、`dpad`

> **架构意义**：开发期不需要碰 IOHIDManager / 任何 Driver Extension / 任何私有 SPI。开源参考实现 ps5-dualsense-mac-trackpad 因语言限制只能走 pygame + hidapi，但**原生的 GameController 框架才是首选**，零依赖、体积小、能耗低。

### 3.2 Q2 — 怎么隐藏 Dock 图标？

**结论：双重保险。**

1. **Info.plist 必须设置 `LSUIElement = true`**，否则即便只用了 MenuBarExtra，Dock 与 ⌘Tab 都会出现。Apple Docs 明文：*"a common behavior is for the app to not display its icon in either the Dock or the application switcher. To enable this behavior, set the LSUIElement flag in your app's Information Property List file to true."*

2. **App 声明里只放 `MenuBarExtra` 一个 Scene**，不放 `WindowGroup`（除非用 `Settings` Scene，因为 SwiftUI 自动管理其窗口）。如果放了 `WindowGroup` 用户关窗时有可能让 App 退出。

不要用 `NSApp.setActivationPolicy(.accessory)` 兜底——`LSUIElement` 在启动期就生效，比运行时切换更干净。

### 3.3 Q3 — CGEvent 的权限模型与限制

**结论：两条权限 + 一个工程约束。**

| 权限 | 检测 | 请求 | 何时触发 | 失败现象 |
|------|------|------|----------|----------|
| Accessibility | `AXIsProcessTrusted()` | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` | 任何 `CGEvent.post()` 投递到其他 App 时 | 事件**静默丢弃**，无报错——开发期最容易踩 |
| Input Monitoring | `CGPreflightListenEventAccess()` | `CGRequestListenEventAccess()` | macOS 10.15+ 起 CGEventTap 监听需要 | **无回调**，同静默 |
| Bluetooth | 系统已配对的设备无需新增；若需扫描新设备，未来加 `IOBluetooth` | — | v1 不需要 | — |

> 关键事实：Apple DTS Quinn 在 2022 年 [官方答疑](https://developer.apple.com/forums/thread/707680) 中明确指出 —— *"the former [NSEvent global monitor] requires the Accessibility privilege whereas the latter [CGEventTap] requires the Input Monitoring privilege. The Input Monitoring privilege is easily available to sandboxed apps, and even apps published on the Mac App Store."*

**工程约束**：CGEvent 合成频率没有硬性上限，但工业界经验是单核持续合成不超过 ~200 events/s 否则可能触发系统"事件洪水"保护。鼠标移动需要按 `deltaTime` 平滑插值，禁止每 frame 都 `post`。

**对 v1 沙盒策略的影响**：Menu Bar App 不上 Mac App Store 时可**关掉沙盒**，让权限请求更轻、便于调试。v1 MVP 不上 App Store，配置 `com.apple.security.app-sandbox = false`。

### 3.4 Q4 — Accessibility 引导流程

**两步法（最佳实践）**：

1. **启动期自检**：`AXIsProcessTrusted()` 返回 false 时，弹引导窗（自定义 SwiftUI View），按钮点击调用 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)`。系统会弹原生授权对话框（或引导去系统设置）。
2. **轮询防回退**：进入主页后，1.5s timer 持续轮询权限，被用户撤销时立即在菜单栏弹窗里出**橙底警告条**。macOS 系统更新后权限可能回退，必须做这一步。

**键盘字符级 CGEvent 不能用 NSEvent.characters 取**：必须在主线程；多线程会触发 `isIGetInputSourceRef` 崩溃。架构上 ControllerEngine 投递 action 时应 `DispatchQueue.main.async` 把映射后的 CGEvent 派发到 main。

### 3.5 Q5 — GCDualShockGamepad 完整按键面

```
        L1 ─────────── R1
       ╱                  ╲
      ╲                    ╱
   ┌──────────────────────┐
   │  △                   │
   │ □  ✕      (TOUCH)   │ ← touchpad (button + 2 finger)
   │  ○                   │
   │      L2  R2          │ ← L2/R2: Float 0...1 (模拟值，可映射到"按下量")
   │      ◯    ◯         │
   │      stick stick     │
   │                      │
   │   SHARE  OPTIONS     │
   │       PS            │
   │       ◯             │
   │  D-PAD  (U D L R)   │
   └──────────────────────┘
       L3 (=左摇按下)   R3 (=右摇按下)
```

**架构对应**：
- DS4 的按键枚举将在 §6 数据模型里映射为 `ControllerButton`（约 15 项）
- L2/R2 可读模拟值 → 可作为**渐进式**触发器（如 L2 按下 30% 以上 = L1 半按下）
- touchpadPrimary.x ∈ [-1,1] + touchpadPrimary.y ∈ [-1,1] → 可作为 2D 映射输入（如手势）

---

## 4. 技术选型矩阵

每个维度均给出 3 个候选 + 评分 + 最终决定 + 决定理由 + 排除备选原因。

### 4.1 进程入口（@main 架构）

| 选项 | 学习成本 | 生态 | 复杂度 | 评分 | 决定 |
|------|---------|------|--------|------|------|
| **A. 纯 SwiftUI `@main App`** | 低 | Apple 一线 | 低 | ★★★★★ | ✅ 选定 |
| B. `NSApplicationMain` + AppKit delegate | 中 | 老派 | 中 | ★★★ | — |
| C. SwiftUI App + `@NSApplicationDelegateAdaptor` | 中 | 混合 | 中 | ★★★★ | — |

**选定 A**：菜单栏 App 标准做法，B 需要手写一堆 AppKit lifecycle 代码，C 仅当我们需要深入 NSStatusItem 私有能力时（我们用 MenuBarExtra 不需要）。

### 4.2 菜单栏实现

| 选项 | API 稳定性 | 自定义 UI | 灵活度 | 评分 | 决定 |
|------|-----------|----------|--------|------|------|
| **A. `MenuBarExtra(style: .window)`** | macOS 13+ 官方稳定 | 任意 SwiftUI | 高 | ★★★★ | ✅ 选定 |
| B. `MenuBarExtra(style: .menu)` | 同上 | 仅原生 Menu | 低 | ★★★ | — |
| C. `NSStatusItem + NSPopover`（AppKit 手动） | 老派稳定 | 任意 | 最高 | ★★★ | — |

**选定 A(`.window` 风格)**：可视化键位编辑器需要 SwiftUI 全套控件（Canvas、Form、Slider、Picker），仅 `.menu` 风格做不到；C 工作量翻倍且需写 AppKit-SwiftUI 双向状态桥，MVP 收益不抵。

### 4.3 PS4 接入

> ⚠️ 最终实现未采用 `GameController.framework`，改为 `IOHIDManager` 直接读 HID 报告（见 [ADR-008](decisions/ADR-008-controller-hid-manager.md)）。

| 选项 | 平台识别 | 性能 | 代码量 | 评分 | 决定 |
|------|---------|------|--------|------|------|
| **A. `GameController.framework` → `GCDualShockGamepad`** | macOS 11+ 原生 | 蓝牙延迟低 | ≤ 100 行 | ★★★★★ | —（规划，被 ADR-008 替代） |
| B. `IOHIDManager` 直接读 HID 报告 | 全平台 | 高 | ≥ 500 行 | ★★ | ✅ 实际采用（见 ADR-008） |
| C. 私有 DualShock4PID / DualSense4PID 枚举 | 反向工程 | 高 | ≥ 1000 行 | ★ | — |

> **注**：规划期选定 A，但因 macOS 26 的 GameController.framework 缺陷，最终实现改为 B（IOHIDManager），见 [ADR-008](decisions/ADR-008-controller-hid-manager.md)。

### 4.4 事件合成

| 选项 | 跨 App 投递 | 系统级权限要求 | 评分 | 决定 |
|------|-----------|---------------|------|------|
| **A. `CGEvent.post(tap: .cgSessionEventTap)`** | 会话级 | Accessibility | ★★★★★ | ✅ 选定 |
| B. `Quartz Event Services` 同 CGEvent | 同 A | 同 A | ★★★★★ | 同 A |
| C. `XCUITest` 私有 XPC | 否 | — | ★ | — |

**选定 A**：Quartz Event Services 是 CGEvent 的子集命名空间，二者在 macOS 上是同一组 API。XCUITest 是测试框架，生产路径不可用。

### 4.5 配置持久化

| 选项 | 适用规模 | 学习成本 | 评分 | 决定 |
|------|---------|---------|------|------|
| A. `@AppStorage / UserDefaults` | 简单 KV | 最低 | ★★★★ | 部分选（设灵敏度等原子偏好）|
| **B. `Codable + JSONEncoder/Decoder` → Application Support 文件** | 中等结构化对象图 | 低 | ★★★★★ | ✅ 选为主（profile 持久化）|
| C. SwiftData (`@Model`) | 关系型 + 查询 | 中 | ★★★ | — |
| D. Core Data | 复杂迁移 | 高 | ★★ | — |

**混合方案 A + B**：灵敏度的浮点数 / 选中态用 `@AppStorage`（"isRunning"、"currentProfileId"、"stickSensitivity"），Profile 整套（按钮→动作映射表、名称、图标）用 Codable JSON 文件，路径 `~/Library/Application Support/DS4Mate/profiles/{uuid}.json`。

排除 SwiftData：Profile 单文档 < 50KB，不需要跨实体查询，SwiftData 的 `ModelContainer` 启动开销 + schema migration plan 治理是过度工程。

### 4.6 项目结构

| 选项 | 单文件 ≤ 300 行约束 | 维护成本 | 评分 | 决定 |
|------|-------------------|---------|------|------|
| **A. Swift Package（Package.swift）+ 单一 executable target** | 容易约束 | 低 | ★★★★★ | ✅ 选定 |
| B. Xcode project（.xcodeproj） | 需管理 pbxproj | 中 | ★★★ | — |
| C. Tuist / XcodeGen 工程生成 | 灵活 | 高 | ★★★ | — |

**选定 A**：仓库实际以 SwiftPM 组织，`Package.swift` 定义 executable target `DS4Mate`；菜单栏 App 经 `swiftc` 编译后由 `scripts/build.sh` 手搓 `.app` bundle 并签名，无需 Xcode 工程文件（见 [ADR-009](decisions/ADR-009-project-structure.md)）。

### 4.7 测试框架

| 选项 | 范围 | 评分 | 决定 |
|------|------|------|------|
| **A. XCTest（单元）+ ViewInspector（SwiftUI 视图）** | 全 | ★★★★★ | ✅ 选定 |
| B. SnapshotTesting 截图回归 | UI | ★★★ | 可选引入 |
| C. Appium / XCUITest e2e | 端到端 | ★★ | — |

**选定 A**：纯单元 + 视图测试 + 手工 e2e（因为测试 CGEvent post 无法 e2e 自动化，需要真机鼠标交互）。

### 4.8 本地化与首次启动

| 选项 | 切换是否即时生效 | 构建改动 | 缺词条时的表现 | 评分 | 决定 |
|------|-----------------|---------|---------------|------|------|
| A. `.lproj` + `Localizable.strings`（系统标准方案） | ❌ 需重启进程（bundle 缓存 locale） | 需在 `build.sh` 里多拷一层资源目录 | 回落到 `key` 原文 | ★★★ | — |
| **B. 运行时双语词典（Swift 字典 + `ObservableObject`）** | ✅ 点一下立刻变 | 无（纯代码） | 回落另一种语言 | ★★★★★ | ✅ 选定 |
| C. 第三方库（如 SwiftGen / Lokalise SDK） | 多数仍需重启 | 引入依赖 | — | ★★ | — |

**选定 B**：这个 App 由 `scripts/build.sh` 手工组装 bundle、无 Xcode 工程，方案 A 需要额外维护资源目录与 locale 解析；更关键的是「设置里点一下就换语言」是明确的产品要求，而 A 必须重启进程。代价是词条表要自己维护，用 `scripts/check-i18n.py` 在构建期做一致性门禁（中英 key 集合相等、占位符相等、无空值、无孤儿引用）。

约定：

- 视图持有 `@ObservedObject private var i18n = Localization.shared`，语言变化时 SwiftUI 自然重算，不依赖环境注入；
- 模型层（`Action` / `ControllerInput` / `ShortcutCatalog`）只存语义或本地化 key，取显示名时现算——不把译文写进数据；
- HID 层状态存 `statusKey + args` 而非成品文案，切换语言后状态行同步刷新；
- 窗口标题这类不经过 `@ObservedObject` 的文案，由 `AppState` 转发 `Localization.objectWillChange` 触发重算。

首次启动的弹窗路径（`FirstRunCoordinator`）：App 是 `LSUIElement`，启动时没有任何窗口，`openWindow(id:)` 又只能在已有视图的 environment 里调用，因此用 AppKit `NSWindow` + `NSHostingController` 直接托管 SwiftUI 视图。顺序为「无语言偏好 → 语言选择窗口 → 未完成引导 → 4 步引导」。

---

## 5. 系统权限模型

### 5.1 权限需求（按重要性）

| # | 权限 | TCC Service | 为什么需要 | 没拿到会怎样 |
|---|------|-------------|-----------|-------------|
| 1 | **Accessibility** | `kTCCServiceAccessibility` | `CGEvent.post()` 投递到其他 App 必须 | 鼠标键盘事件**静默丢弃**，用户无感知 |
| 2 | **Bluetooth (always-on system)** | 系统维护 | 系统蓝牙栈已持有，无需 App 额外申请 | 用户配对手柄会被 macOS 直接广播给 GameController.framework |
| 3 | **Input Monitoring** | `kTCCServiceListenEvent`（macOS 10.15+） | 未来若要加 CGEventTap 拦截（如截获系统 Fn 键） | 仅合成不需要；v1 可不申请 |

> macOS 13 与 14 在权限上的差异：14 加了 `CGRequestListenEventAccess` 函数（早期版本无）；14 还强制 App 必须签名才能出现在 Input Monitoring 列表。开发期用 `ad-hoc` 签名即可被看见。

### 5.2 检测 → 引导 → 轮询三段式

```
App 启动
  │
  ▼
PermissionManager.bootstrap()
  ├─ accessibility = AXIsProcessTrusted()
  ├─ inputMonitoring = CGPreflightListenEventAccess()
  ├─ bluetooth = (via system, no API)
  └─ 状态写入 @Observable AppState.permissions
        │
        ▼
  任一缺失 → 首次进入 OnboardingView（SwiftUI）
        │
        ▼
  用户点 "Request Accessibility"
        ▼
  AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])
        │
        ▼
  系统弹原生对话框 / 引导去系统设置
        │
        ▼
  1.5s timer 持续轮询
        │
        ▼
  状态回退时菜单栏弹窗出橙底警告条
```

### 5.3 权限被拒时的优雅降级

- Accessibility 未授权 → 引擎 `ActionDispatcher` 设 `mode = .noop`，所有按键不生效，菜单栏图标变 `exclamationmark.triangle`
- 用户始终拒 → 在 Settings 里提供 "Open Accessibility Settings" 跳转按钮（`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`）
- 永远不自动重新发起权限请求（系统限制每个进程只能弹一次原生 prompt）

---

## 6. 核心数据模型（Swift 伪代码）

> 按"领域实体 → 行为入口 → 持久化形态"顺序自上而下；非实现，是契约。

```swift
// MARK: - 6.1 控制器按键（PS4 DualShock 4 全按钮/轴）

public enum ControllerButton: String, Codable, CaseIterable, Identifiable {
    // 十字键
    case dpadUp, dpadDown, dpadLeft, dpadRight
    // 面部键
    case buttonA = "cross"        // PS4 的 ×
    case buttonB = "circle"       // PS4 的 ○
    case buttonX = "square"       // PS4 的 □
    case buttonY = "triangle"     // PS4 的 △
    // 肩键
    case leftShoulder  // L1
    case rightShoulder // R1
    case leftTrigger   // L2（Float 0..1）
    case rightTrigger  // R2（Float 0..1）
    // 摇杆 + 摇杆按压
    case leftThumbstickUp, leftThumbstickDown, leftThumbstickLeft, leftThumbstickRight
    case rightThumbstickUp, rightThumbstickDown, rightThumbstickLeft, rightThumbstickRight
    case leftThumbstickButton  // L3
    case rightThumbstickButton // R3
    // 中部
    case touchpadButton   // DS4 触控板按键
    case share, options, ps
    // 摇杆本身的 2D 坐标（可选映射为鼠标/手势）
    case leftStick2D
    case rightStick2D
    case touchpadPrimary2D
    // 触发量（用于"按下到 N% 触发某动作"的进阶映射）
    case leftTriggerAnalog   // 暴露模拟值
    case rightTriggerAnalog

    public var id: String { rawValue }

    /// SF Symbols 对应图标（必须查 mapping-table，没找到时回退 generic circle）
    public var symbol: String { /* 详见附录 A */ }
}

// MARK: - 6.2 可执行动作（鼠标/键盘/系统命令）

public enum Action: Codable, Hashable {
    case mouseLeftClick
    case mouseRightClick
    case mouseMiddleClick
    case mouseDoubleClick
    case mouseMove(dx: Float, dy: Float, smoothing: Float)   // 摇杆 → 鼠标
    case scroll(dx: Float, dy: Float)
    case key(keyCode: UInt16, modifiers: Modifiers)
    case hotkey(keyCode: UInt16, modifiers: Modifiers)       // 仅在 pressed/down 触发
    case shell(String)                                       // 警告：v1 不开

    public struct Modifiers: OptionSet, Codable, Hashable {
        public let rawValue: Int
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option  = Modifiers(rawValue: 1 << 1)
        public static let shift   = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }
}

// MARK: - 6.3 映射规则（按钮 → 动作）

public struct ButtonMapping: Codable, Hashable, Identifiable {
    public var id: UUID
    public var button: ControllerButton
    public var action: Action
    /// 0..1；如 L2 触发"瞄准"需按下 60% 才生效
    public var triggerThreshold: Float?
    /// false = 按下触发；true = 持续（每 16ms 重发，慎用）
    public var repeatWhileHeld: Bool

    public init(button: ControllerButton, action: Action,
                threshold: Float? = nil, repeatWhileHeld: Bool = false) { … }
}

// MARK: - 6.4 Profile（一组完整映射）

public struct MappingProfile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String                  // 用户看到的名字 "FPS / Editing"
    public var symbol: String                // SF Symbol 用于菜单栏区分
    public var stickSensitivity: Float       // 鼠标速度，存 @AppStorage 同名
    public var scrollSensitivity: Float
    public var mappings: [ButtonMapping]
    public var createdAt: Date
    public var updatedAt: Date
}

// MARK: - 6.5 App 全局状态（@Observable 全局单例）

@MainActor
@Observable
public final class AppState {
    public var permissionStatus: PermissionStatus = .unknown
    public var connectedController: GCDualShockGamepad?
    public var availableControllers: [GCController] = []
    public var profiles: [MappingProfile] = []
    public var activeProfileId: UUID?       // 同步 @AppStorage("activeProfileId")
    public var isMappingEnabled: Bool       // 同步 @AppStorage("isMappingEnabled")
    public var lastEvent: DebugEvent?       // 仅 DEBUG 显示

    public var activeProfile: MappingProfile? { … }  // 计算属性

    public func selectProfile(_ id: UUID) { … }
    public func upsertMapping(_ m: ButtonMapping) { … }
}

// MARK: - 6.6 权限状态

public struct PermissionStatus: Codable, Hashable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var bluetoothReady: Bool   // 是否有任意 GCController 在线
    public var allGranted: Bool { accessibility && inputMonitoring }
}

// MARK: - 6.7 持久化接口

public protocol ProfileStore {
    func loadAll() throws -> [MappingProfile]
    func save(_ profile: MappingProfile) throws
    func delete(id: UUID) throws
    func setActive(_ id: UUID) throws
}

/// CodableJSONProfileStore 写入 ~/Library/Application Support/DS4Mate/profiles/{uuid}.json
public final class CodableJSONProfileStore: ProfileStore { … }
```

**架构分层**：
- `ControllerButton` / `Action` / `ButtonMapping` / `MappingProfile` —— `Models` 层，纯值类型，`Codable`
- `AppState` —— `App/State` 层，`@Observable`，全 App 唯一
- `ProfileStore` + 实现 —— `Persistence` 层，无业务逻辑
- `Engine` 与具体解析留给后文

---

## 7. 项目文件结构（Xcode 工程目录树）

> ⚠️ 本节为规划期的 Xcode 工程目录设想；实际仓库采用 SwiftPM（`Package.swift` + `Sources/DS4Mate/...`），见 [ADR-009](decisions/ADR-009-project-structure.md)。

> 单文件 ≤ 300 行硬规则限制了深层嵌套。下面是**目标分组结构**，每个 .swift 文件平均约 150–250 行。

```
projects/ds4mate/
├── README.md
├── docs/
│   ├── architecture.md            ← 本文档
│   ├── prd.md                     ← PM 产出
│   ├── decisions/
│   │   ├── ADR-001-tech-stack.md
│   │   ├── ADR-002-menubar-pattern.md
│   │   ├── ADR-003-controller-framework.md
│   │   ├── ADR-004-event-synthesis.md
│   │   ├── ADR-005-persistence.md
│   │   ├── ADR-006-project-structure.md
│   │   ├── ADR-007-testing.md
│   │   └── mapping-profile.schema.json  ← 机器可读契约（替代 openapi.yaml）
│   └── adr-index.md
├── DS4Mate/                       ← Xcode project root
│   ├── DS4Mate.xcodeproj
│   ├── DS4Mate.entitlements
│   ├── Info.plist                 ← 含 LSUIElement, NSAppleEventsUsageDescription
│   ├── Resources/
│   │   ├── Assets.xcassets        ← AppIcon + 模板 icon variants
│   │   ├── DS4MateProfile.json    ← 内置默认 profile (FPS、Editing)
│   │   └── Localizable.strings
│   └── Sources/
│       ├── App/
│       │   ├── DS4MateApp.swift           ← @main + Scene 配置（单文件，~120 行）
│       │   └── AppDelegate.swift          ← NSApplicationDelegate 适配器（仅需 Ctrl-Win 唤醒）
│       ├── Controller/
│       │   ├── ControllerDiscovery.swift  ← GCController.controllers 监听
│       │   ├── ControllerEventStream.swift← 单一 GCController → AsyncStream<RawEvent>
│       │   └── RawControllerEvent.swift   ← 抽象每帧按键状态
│       ├── Engine/
│       │   ├── MappingEngine.swift        ← 订阅 RawEvent → dispatch Action
│       │   ├── ActionDispatcher.swift     ← 把 Action 翻译成 CGEvent 并投递
│       │   ├── StickSmoother.swift        ← 摇杆 → 鼠标的平滑 + 死区
│       │   └── TriggerFilter.swift        ← L2/R2 阈值过滤
│       ├── Models/                        ← §6 数据模型，单独目录，依赖最少
│       │   ├── ControllerButton.swift
│       │   ├── Action.swift
│       │   ├── ButtonMapping.swift
│       │   ├── MappingProfile.swift
│       │   └── PermissionStatus.swift
│       ├── Persistence/
│       │   ├── ProfileStore.swift         ← protocol
│       │   ├── JSONProfileStore.swift     ← 落盘到 ~/Library/Application Support/DS4Mate/
│       │   └── AppPreferences.swift       ← @AppStorage 包装的 boolean / float
│       ├── Permissions/
│       │   ├── PermissionManager.swift    ← @Observable 包装三种权限
│       │   ├── AccessibilityProbe.swift   ← AXIsProcessTrusted
│       │   ├── InputMonitoringProbe.swift ← CGPreflightListenEventAccess
│       │   └── SystemSettingsRouter.swift ← 跳系统设置
│       ├── UI/
│       │   ├── Components/
│       │   │   ├── IconButton.swift
│       │   │   ├── PermissionWarningBanner.swift
│       │   │   └── ProfilePicker.swift
│       │   ├── Menu/
│       │   │   ├── MenuBarRoot.swift      ← .window 风格的内容 root
│       │   │   ├── MenuStatusView.swift   ← 连接状态、profile 名字、运行开关
│       │   │   └── MenuFooterView.swift   ← Quit / Settings
│       │   ├── Settings/
│       │   │   ├── SettingsRoot.swift     ← TabView: General / Advanced / About
│       │   │   ├── GeneralSettingsView.swift
│       │   │   └── AdvancedSettingsView.swift
│       │   └── Editor/
│       │       ├── ProfileEditorView.swift ← 可视化键位编辑器主入口
│       │       ├── ControllerCanvas.swift  ← 用 Canvas 画 DualShock 4 俯视图
│       │       ├── ActionPickerSheet.swift ← 选中按钮后弹的动作选择面板
│       │       └── SensitivitySlider.swift ← 摇杆灵敏度微调
│       └── Utilities/
│           ├── Logger.swift                ← os.log 包装
│           ├── Throttle.swift              ← 通用节流
│           └── KeyCodes.swift              ← 常用 macOS 虚拟键码常量表
├── DS4MateTests/
│   ├── ControllerTests/
│   │   └── ControllerEventStreamTests.swift
│   ├── EngineTests/
│   │   ├── MappingEngineTests.swift
│   │   ├── StickSmootherTests.swift
│   │   └── TriggerFilterTests.swift
│   ├── PersistenceTests/
│   │   └── JSONProfileStoreTests.swift
│   └── PermissionsTests/
│       └── PermissionManagerTests.swift
└── scripts/
    ├── bootstrap.sh                  ← 首次 setup
    └── make-release.sh               ← codesign + notarytool
```

**目录约束**：
- `Sources/Models/` 不依赖 App/UI/Engine，可被任意层引用
- `Sources/Engine/` 只能依赖 Models + Controller
- `Sources/UI/` 只能依赖 AppState（@Observable）+ Models
- `Sources/Persistence/` 只能依赖 Models
- 单文件硬 ≤ 300 行（CI 用 `swiftlines` 或 `wc -l` 校验）

---

## 8. 关键技术风险与缓解

> 风险按"发生概率 × 影响"排序。

### R1. **macOS 14 Input Monitoring 权限静默失败**（概率：高 / 影响：高）

- **症状**：`CGRequestListenEventAccess()` 调用后无任何 prompt，用户无感知；后续 CGEventTap 不回调。
- **缓解**：
  1. 启动时 `CGPreflightListenEventAccess()` 必须显式调用再判断
  2. 设置页显式列"Input Monitoring 状态 + 申请按钮 + 跳转系统设置"
  3. **可观测性**：tap 安装成功但 1s 内无回调 → 在日志里贴 `sysctl -n kern.osversion` 供用户反馈
  4. 已知 Apple Bug：tap timeout 后会自动 disable，回调里必须再 enable（参考 §3.3 引文）

### R2. **Accessibility 权限被系统更新重置**（概率：中 / 影响：高）

- **症状**：macOS 大版本升级后 App 重新需要被勾选。
- **缓解**：
  1. 启动时轮询（§5.2），回退时弹菜单栏警告条
  2. 文案明确告诉用户"这是 macOS 重置不是你授权取消"
  3. 提供一键"跳到设置"按钮

### R3. **macOS Sonoma 隐私指示器（菜单栏小绿/橙/紫点）**（概率：低 / 影响：中）

- **症状**：系统会在菜单栏出**绿点（摄像头）/ 橙点（麦克风）/ 紫点（录屏）**指示器，但**CGEvent 合成不会触发任何点**——避免误导。
- **缓解**：v1 我们只走 CGEvent 合成不监听 → 不会被点；FAQ 文案内置一句说明。

### R4. **Multi-Display 鼠标移动边界**（概率：中 / 影响：中）

- **症状**：`CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: ...)` 必须传"主屏坐标系"还是"全显示器 union 坐标系"？
- **缓解**：统一用 `CGEvent(source: nil).location` 的返回值坐标系——macOS 默认是**全显示器 union 的逻辑坐标**。Sprint 1 必须用真实双屏测一遍，Xcode Previews 模拟不到。

### R5. **PS4 手柄蓝牙断连重连风暴**（概率：中 / 影响：中）

- **症状**：macOS 偶发把同一手柄广播为两个 controller 对象，新旧对象 input 同时触发，造成按键双发。
- **缓解**：
  1. `ControllerDiscovery` 用 `controller.vendorName + serialNumber` 做去重
  2. 收到 `.disconnect` 后 200ms 再开始接收 `.connect`，给 mDNS 缓存时间
  3. 给 MappingEngine 加"按键事件去抖"——同按钮连续 30ms 内只接受第一次

### R6. **App Sandbox 与非 Mac App Store 分发的冲突**（概率：低 / 影响：中）

- **症状**：开 App Sandbox 后 `.app` 在 Mac App Store 外分发需要 entitlements，但 Accessibility 必须申请。
- **缓解**：v1 MVP **不开沙盒**（参考 §3.3 DTS 答疑，Input Monitoring 即使开沙盒也能拿到，但开发期关沙盒更省事）。v2 再加 App Sandbox + 针对 entitlements 调整。

---

## 9. 开发里程碑

| Sprint | 时长 | 目标 | 关键产出 |
|--------|------|------|---------|
| **Sprint 1：核心链路** | 2 周 | 菜单栏跑起来，手柄可发现，按键→键盘动作可映射 | DS4Mate.app 真机可启动；最少 4 个按键可工作；`Info.plist` + `LSUIElement` 完成；权限引导第一步就绪 |
| **Sprint 2：可视化编辑器** | 2 周 | 菜单栏 .window 弹出可视化编辑器；Profile 切换；摇杆→鼠标完成 | Profile JSON 文件可读写；内置"FPS" 与 "Editing" 两个预设；可视化 DualShock 4 Canvas 渲染 |
| **Sprint 3：打磨 + 发行** | 1.5 周 | 权限引导完整版；包装/签名/公证；TestFlight-like 内部分发 | ad-hoc 签名 + Developer ID 公证脚本；README + 用户手册；Apple 风格的首次启动引导 UI |
| **Sprint 4（可选）** | 1 周 | 用户反馈修复；备份/导入 profile；图标自定义导入 | Profile 的 `.dmp4profile` 打包导出 |

> 启动 base 0：Sprint 1 的"4 个按键可工作"以"Cross=Left Click, Circle=Right Click, Square=Middle Click, Triangle=Enter"为最小可演示集。

---

## 10. 测试策略

| 层级 | 范围 | 工具 | 覆盖目标 |
|------|------|------|---------|
| 单元测试 | `Engine/`、`Persistence/`、`Models/` | XCTest + 内存 ProfileStore fake | ≥ 70% 行覆盖 |
| SwiftUI 视图测试 | `Editor/`、`Menu/`、`Settings/` | ViewInspector | 每个主视图 1 happy-path |
| 权限探测单测 | `Permissions/` | XCTest + 注入 mock probe | ≥ 80% |
| CGEvent 合成单测 | `Engine/ActionDispatcher` | XCTest，注入 in-memory event sink | ≥ 90% — 这块逻辑错会静默失败 |
| 手工 e2e | 真机 + 真手柄 | 手动 + 录屏 | Sprint 1/2/3 各一轮 |
| 烟囱测试 | App 启动 + 菜单栏显示 | XCTest UI 启动 | 1 个 |
| **回归盲区** | "鼠标指针移动" 不可自动测 | 手工 | 真机每个 sprint |

---

## 11. 打包与发布（v1 不上 App Store）

1. **签名**：Developer ID Application（与 Apple 开发者账号绑定）
2. **公证**：`xcrun notarytool submit DS4Mate.app --team-id ... --wait --output-format json`
3. **分发**：直接 `dmg` 打包分发，或 GitHub Release 附 `dmg`
4. **自动更新**：v1 不做，让用户下载新版；v2 调研 [Sparkle](https://github.com/sparkle-project/Sparkle)（约 500 行 Cocoa 集成即可）
5. **崩溃监控**：v1 接 [Sentry macOS SDK](https://github.com/getsentry/sentry-cocoa) 的 SDK + 不上传触摸/按键值的 scrub filter

---

## 附录 A：SF Symbols 图标候选清单

（具体名字待设计师在 Sprint 1 内确认，但下面给出可用基线，确保全项目统一一套图标系统，不引入 emoji。）

| 语义 | SF Symbol |
|------|-----------|
| App 入口 | `gamecontroller.fill` |
| 已连接手柄 | `gamecontroller` |
| 未连接 | `gamecontroller.slash`（不一定存在，回退到 `circle.slash`）|
| 启用映射 | `play.fill` |
| 停用映射 | `pause.fill` |
| Cross (A 键) | `xmark`（文字标识 Cross ×）|
| Circle (B 键) | `circle` |
| Square (X 键) | `square` |
| Triangle (Y 键) | `triangle` |
| L/R Trigger | `l2.rectangle.roundedtop` / `r2.rectangle.roundedtop`（若存在）|
| Settings 入口 | `gear` |
| 编辑 Profile | `square.and.pencil` |
| 删除 Profile | `trash` |
| 警告（权限缺失）| `exclamationmark.triangle` |
| 重连手柄 | `arrow.clockwise` |

> **Fallback 规则**：找不到的 symbol 一律用 `circle`，并在 Logger 里记录一次"missing symbol: xxx"以便回头补齐。永不用 emoji 替代。

---

## 附录 B：关键技术引用

1. Apple Docs — [GCDualShockGamepad](http://docs.developer.apple.com/documentation/gamecontroller/gcdualshockgamepad) — PS4 profile（macOS 11.0+）
2. Apple Docs — [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) — macOS 13+ 官方菜单栏
3. Apple Docs — [Settings Scene](https://developer.apple.com/documentation/swiftui/settings) — 配置窗口
4. Apple Docs — [SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink) — macOS 14.0+
5. Apple DTS Quinn — [Accessibility in sandboxed app](https://developer.apple.com/forums/thread/707680) — Input Monitoring 沙盒可用
6. Apple Forums — [Code signing & CGEvent tap race](https://www.danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race) — tap 健康检查
7. 实战参考 — [ps5-dualsense-mac-trackpad](https://github.com/ianljoun-pixel/ps5-dualsense-mac-trackpad) — Python+pygame+CoreGraphics 行为对照
8. macOS Security — [TCC perms](https://hacktricks.wiki/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-dangerous-entitlements.html) — kTCCServicePostEvent / Accessibility / ListenEvent

---

## 附录 C：ADR 索引

| ADR | 标题 | 状态 |
|-----|------|------|
| [ADR-001](decisions/ADR-001-tech-stack.md) | Swift + SwiftUI 作为主技术栈 | Accepted |
| [ADR-002](decisions/ADR-002-menubar-pattern.md) | MenuBarExtra(.window) + LSUIElement 实现菜单栏 App | Accepted |
| [ADR-003](decisions/ADR-003-controller-framework.md) | 使用 GameController.framework + GCDualShockGamepad 接入 PS4 | **Superseded**（被 ADR-008 替代） |
| [ADR-004](decisions/ADR-004-event-synthesis.md) | 通过 CGEvent 合成鼠标/键盘事件 | Accepted |
| [ADR-005](decisions/ADR-005-persistence.md) | Codable JSON + Application Support 目录持久化 Profile | Accepted |
| [ADR-006](decisions/ADR-006-project-structure.md) | Xcode Project（非 Swift Package）作为工程结构 | **Superseded**（被 ADR-009 替代） |
| [ADR-007](decisions/ADR-007-testing.md) | XCTest + ViewInspector 作为测试基线 | Accepted |
| [ADR-008](decisions/ADR-008-controller-hid-manager.md) | 改用 IOHIDManager 直接读 HID 报告接入 PS4 | Accepted |
| [ADR-009](decisions/ADR-009-project-structure.md) | 采用 Swift Package（Package.swift）作为工程结构 | Accepted |

机器可读契约（替代 openapi.yaml）：[`mapping-profile.schema.json`](decisions/mapping-profile.schema.json)

---

## 附录 D：版本与变更记录

| 日期 | 版本 | 作者 | 变更 |
|------|------|------|------|
| 2026-10-18 | v1.0 草案 | 高见远 | 初版：技术选型 + 5 个联网调研问题 + 数据模型 + 项目结构 |
