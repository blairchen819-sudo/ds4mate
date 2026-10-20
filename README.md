# DS4Mate

> 把 PS4 DualShock 4 手柄变成 Mac 的鼠标/键盘遥控器，原生 SwiftUI 菜单栏 App。

**状态**：v1.0 MVP 已完成，90/90 冒烟测试通过，可启动运行。

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

期望输出：`通过：90 / 失败：0`

---

## 功能特性

| 类别 | 功能 |
|------|------|
| **连接** | 蓝牙自动连接 PS4 DualShock 4，PS4 关机后自动重连 |
| **菜单栏** | 常驻菜单栏图标，启停开关，Profile 切换，权限状态 |
| **默认映射** | 3 套预设：默认（鼠标键盘）/ 媒体遥控（音量+播放）/ 演示（幻灯片+激光笔） |
| **可视化编辑** | 6 步点击即可改任意按键映射（22 个输入 × 28 个动作） |
| **持久化** | JSON 配置文件存于 `~/Library/Application Support/DS4Mate/profiles/` |
| **安全** | CGEvent 合成（仅需 Accessibility），不做网络请求，不读任何用户文件 |
| **数据** | 用户自定义 Profile 支持自动备份损坏文件 |

---

## 技术栈

- **语言**：Swift 5.9+ / SwiftUI
- **最低系统**：macOS 13 Ventura
- **推荐系统**：macOS 14 Sonoma（完整 MenuBarExtra 能力）
- **PS4 接入**：Apple 原生 `GameController.framework` → `GCDualShockGamepad`
- **事件合成**：CoreGraphics `CGEvent.post(tap: .cgSessionEventTap)`
- **持久化**：Codable JSON + @AppStorage
- **打包**：手搓 `.app` bundle + ad-hoc 签名（绕开无 Xcode 限制）

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
  ↓ 蓝牙
[GameController.framework]
  ↓ GCExtendedGamepad 回调
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
4. **未签名**：当前是 ad-hoc 签名，Gatekeeper 会弹警告（首次打开需右键 → 打开）

---

## 路线图

- v1.0（MVP，当前）：蓝牙连接 + 3 套预设 + 可视化编辑
- v1.1：死区/灵敏度调节 + JSON 导入导出 + 反向/互换
- v1.2：多 Profile（同时多套切换）
- v2.0：Xbox/PS5/Switch Pro 支持 + 宏录制 + USB 有线

---

## 许可

MIT License
