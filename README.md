# DS4Mate

> 把 PS4 DualShock 4 手柄变成 Mac 的鼠标/键盘遥控器，原生 SwiftUI 菜单栏 App。

**状态**：v1.0 MVP 已完成，90/90 冒烟测试通过，可启动运行。

> **说明**：DS4Mate 是带图形界面的 macOS **菜单栏 App**（`@main App` + `MenuBarExtra`，打包为 `.app` 运行），**不是命令行 / 终端程序**，没有 CLI 参数或终端交互界面。

---

## 快速开始

### 安装与运行

```bash
# 1. 构建
./scripts/build.sh

# 2. 启动 App
open build/DS4Mate.app

# 3. 首次启动会弹出 4 步引导：
#    - 欢迎
#    - 授权辅助功能（系统设置 → 隐私与安全性 → 辅助功能，勾选 DS4Mate.app）
#    - 配对 PS4 手柄（按住 Share + PS 进入配对模式）
#    - 试玩默认映射

# 4. 推动右摇杆 = 移动鼠标
# 5. 按 × = 鼠标左键
# 6. 按 Options 1 秒 = 退出
```

### 运行测试

```bash
./build/DS4MateTests
```

期望输出：`通过：95 / 失败：0`

---

## 功能特性

| 类别 | 功能 |
|------|------|
| **连接** | 蓝牙自动连接 PS4 DualShock 4，PS4 关机后自动重连 |
| **菜单栏** | 常驻菜单栏图标，启停开关，Profile 切换，权限状态 |
| **预设** | 不内置固定预设，全部由你自建；首次启动自动生成一份可编辑的初始预设（鼠标键盘映射） |
| **可视化编辑** | 6 步点击即可改任意按键映射（22 个输入 × 28 个动作） |
| **持久化** | JSON 配置文件存于 `~/Library/Application Support/DS4Mate/profiles/` |
| **预设管理** | 编辑器内可把当前键位「另存为」任意命名的新预设；多套预设可在编辑器选择器或菜单栏直接切换 |
| **一键切换** | 可指定一个手柄按键作为「切换预设键」，任何预设下按下即切到下一套（换预设后依然有效） |
| **安全** | CGEvent 合成（仅需 Accessibility），不做网络请求，不读任何用户文件 |
| **数据** | 用户自定义 Profile 支持自动备份损坏文件 |
| **桌面切换** | 通过调度中心（Spaces）切换虚拟桌面，配合「上一个 / 下一个桌面」系统快捷键预设 |
| **千问语音控制** | 一键开关通义千问（Qwen）语音通话与麦克风静音；走辅助功能（AX）点击其通话按钮，自动跨桌面切换并切回原窗口 |

---

## 技术栈

- **语言**：Swift 5.9+ / SwiftUI
- **最低系统**：macOS 13 Ventura
- **推荐系统**：macOS 14 Sonoma（完整 MenuBarExtra 能力）
- **PS4 接入**：`IOKit` / `IOBluetooth` 的 `IOHIDManager` 直接解析蓝牙 HID 报告（vendor `0x054C`，pid `0x09CC`/`0x05C4`/`0x0CE6`）。_注：早期方案计划用 `GameController.framework`，但 macOS 26 上该框架的 PS4 事件流存在 bug，最终改走 IOHIDManager 绕过，详见 `Sources/DS4Mate/Services/HIDControllerService.swift` 顶部注释。_
- **事件合成**：CoreGraphics `CGEvent.post(tap: .cgSessionEventTap)`
- **持久化**：Codable JSON + @AppStorage
- **打包**：手搓 `.app` bundle + 自签证书 `DS4Mate Local Signing`（固定签名身份，避免 TCC 在每次重建后使「辅助功能 / 输入监控」授权失效；无证书时回退 ad-hoc，见 `scripts/build.sh`）

---

## 目录结构

```
ds4mate/
├── docs/                          # 全部文档
│   ├── SPEC.md                    # 规格即契约（v1.0 锁定）
│   ├── OPEN-DECISIONS.md          # 5 个决策全 RESOLVED
│   ├── architecture.md            # 技术架构（650 行）
│   ├── DESIGN.md                  # UI/UX 设计（1028 行）
│   ├── research/PRD-v0.1.md       # PM 调研
│   ├── design-tokens.json         # W3C 标准设计 Token
│   ├── design-system/             # 6 个页面范式
│   ├── decisions/                 # 7 个 ADR + JSON Schema
│   └── adr-index.md
├── Sources/DS4Mate/
│   ├── App/                       # @main + AppState
│   ├── Models/                    # 数据模型
│   ├── Services/                  # ControllerService / EventSynthesizer 等
│   ├── Views/                     # SwiftUI 视图
│   └── Resources/                 # Info.plist + 3 个 JSON Profile
├── Tests/RunTests.swift           # 90 个冒烟测试
├── scripts/build.sh               # 一键构建脚本
├── Package.swift                  # SwiftPM 定义
└── build/                         # 编译产物
    ├── DS4Mate                    # 独立可执行（1MB）
    ├── DS4Mate.app                # .app bundle（可双击运行）
    └── DS4MateTests               # 测试可执行
```

---

## 数据流

```
[PS4 手柄]
  ↓ 蓝牙 (HID)
[IOHIDManager]  ← 直接读 HID 报告（绕过 macOS 26 的 GameController.framework 缺陷）
  ↓ HID 报告解析
[ControllerService] ← 持有 [Profile] (active)
  ↓ 查 binding(for: input)
[EventSynthesizer]
  ↓ CGEvent.post
[macOS 输入系统]
  ↓
[前台 App]
```

---

## 已知限制

1. **媒体键未实现**：v1 走 print 提示（`Cmd+Space` 等键盘模拟替代），完整实现需走私有 NSEvent
2. **PS4 触摸板手势未做**：v1 仅消费 `touchpadButton` 单点，多指手势 v1.1 候选
3. **PS 键在 GCDualShockGamepad 上不可读**：macOS GameController 框架未暴露 PS/Share/Options 按键，v1 通过反射拿 `shareButton`/`optionsButton` 私有路径
4. **未上架 App Store / 无 Apple 开发者证书**：用本机自签（无证书时回退 ad-hoc）；Gatekeeper 首次打开会弹警告，需右键 → 打开
5. **千问语音控制依赖 UI 布局**：通过辅助功能读取千问（Qwen）窗口的按钮，依赖其界面布局与「辅助功能」授权；千问改版或窗口不在当前桌面时可能失效（已做跨桌面切换兜底）

---

## 路线图

- v1.0（MVP，当前）：蓝牙连接 + 多预设管理（全部用户自建）+ 可视化编辑
- v1.1：死区/灵敏度调节 + JSON 导入导出 + 反向/互换
- v1.2：多 Profile（同时多套切换）
- v2.0：Xbox/PS5/Switch Pro 支持 + 宏录制 + USB 有线

---

## 许可

MIT License
