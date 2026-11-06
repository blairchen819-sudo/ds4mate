# DS4Mate

> **Use a PS4 DualShock 4 as a mouse, keyboard and shortcut remote on macOS.**
> Native SwiftUI menu bar app with visual button mapping, swappable profiles and a bilingual (English / 简体中文) UI.
>
> 把 PS4 DualShock 4 手柄变成 Mac 的鼠标 / 键盘 / 快捷键遥控器，原生 SwiftUI 菜单栏 App，界面支持中英双语。

**状态**：v1.2 已完成，211/211 冒烟测试通过，可启动运行。

> **说明**：DS4Mate 是带图形界面的 macOS **菜单栏 App**（`@main App` + `MenuBarExtra`，打包为 `.app` 运行），**不是命令行 / 终端程序**，没有 CLI 参数或终端交互界面。

---

## 快速开始

### 安装与运行

```bash
# 1. 构建
./scripts/build.sh

# 2. 启动 App
open build/DS4Mate.app

# 3. 首次启动先弹语言选择（English / 简体中文，点一下即生效，之后可在「设置 → 通用」改）
# 4. 选完语言接着走 4 步引导：
#    - 欢迎
#    - 授权辅助功能（系统设置 → 隐私与安全性 → 辅助功能，勾选 DS4Mate.app）
#    - 配对 PS4 手柄（按住 Share + PS 进入配对模式）
#    - 试玩默认映射

# 5. 推动右摇杆 = 移动鼠标
# 6. 按 × = 鼠标左键
# 7. 按 Options 1 秒 = 退出

# 8. 可选：菜单栏图标 → 设置 → 通用 → 触摸板 → 打开「触摸板当鼠标」
#    之后手指在触摸板上滑动 = 移动指针，轻按触摸板 = 鼠标左键，
#    双指滑动 = 滚动，双指张开 / 收拢 = 放大 / 缩小
```

### 运行测试

```bash
./build/DS4MateTests
```

期望输出：`通过：211 / 失败：0`

---

## 功能特性

| 类别 | 功能 |
|------|------|
| **连接** | 蓝牙自动连接 PS4 DualShock 4，PS4 关机后自动重连 |
| **菜单栏** | 常驻图标 + 当前预设名（过长自动截断），启停开关，Profile 切换，权限状态 |
| **预设** | 不内置固定预设，全部由你自建；首次启动自动生成一份可编辑的初始预设（鼠标键盘映射） |
| **可视化编辑** | 6 步点击即可改任意按键映射（22 个输入 × 5 类动作：鼠标 / 键盘 / 系统快捷键 / 媒体 / 应用） |
| **持久化** | JSON 配置文件存于 `~/Library/Application Support/DS4Mate/profiles/` |
| **预设管理** | 编辑器内可把当前键位「另存为」任意命名的新预设；多套预设可在编辑器选择器或菜单栏直接切换；可删除单份预设（菜单栏每行垃圾桶 / 编辑器「删除预设」），最后一份不允许删 |
| **一键切换** | 可指定一个手柄按键作为「切换预设键」，任何预设下按下即切到下一套（换预设后依然有效） |
| **安全** | CGEvent 合成（仅需 Accessibility），不做网络请求，不读任何用户文件 |
| **数据** | 用户自定义 Profile 支持自动备份损坏文件 |
| **桌面切换** | 通过调度中心（Spaces）切换虚拟桌面，配合「上一个 / 下一个桌面」系统快捷键预设 |
| **触摸板鼠标** | 手指在触摸板上滑动即可移动指针，轻按触摸板 = 鼠标左键。走 IOKit 原始 HID，每包解 3~4 个触摸采样（有效 200+Hz）+ 时间插值 + 速度自适应低通 + 240Hz 合成 CGEvent；灵敏度 / 平滑度 / 死区可调 |
| **抬指即止** | 手指离开触摸板光标立刻停住，换个区域重新按下光标**原地不动**，从新位置继续相对移动 —— 与 Mac 内置触摸板一致。无触摸帧 / 触点编号变化 / 瞬时断触三重判定，正常快速滑动不会被误判 |
| **双指手势** | 双指滑动 = 滚动，双指张开 / 收拢 = 放大 / 缩小（`⌘=` / `⌘-`）。按 touchID 分组识别并行触点；双指期间指针自动冻结。滚动速度 / 缩放灵敏度 / 反转方向可调。详见 `docs/touchpad-mouse.md` |
| **千问语音控制** | 一键开关通义千问（Qwen）语音通话与麦克风静音；走辅助功能（AX）点击其通话按钮，自动跨桌面切换并切回原窗口 |
| **讯飞语音输入** | 一键唤起 / 关闭讯飞输入法的语音输入；AX 定位语音面板并点击其麦克风按钮 |
| **双语界面** | 英文 / 简体中文，首次启动先选语言，之后在「设置 → 通用」随时切换，**点一下即时生效，不用重启**；词条表由 `scripts/check-i18n.py` 在构建时校验中英一一对应 |

---

## 两套现成配置（`examples/`）

`examples/` 下有两套可以直接用的按键映射。它们不是演示数据，是把「手柄当遥控器」真正落地后的配置：

| 文件 | 目标应用 | 使用姿态 |
|------|----------|----------|
| `examples/workbuddy.json` | WorkBuddy 桌面端 | 躺着聊 AI：发消息、切任务、切侧栏、切桌面 |
| `examples/orca.json` | Orca 终端 | 躺着写代码：跑命令、Tab 补全、切 worktree、切标签 |

### 用法

```bash
cp examples/workbuddy.json examples/orca.json \
   "$HOME/Library/Application Support/DS4Mate/profiles/"
```

重启 App，菜单栏的预设列表里就会出现这两套。两份文件用的是固定 UUID（`57fb2566-…` / `75925c45-…`），与本机已有预设互不冲突；重复拷贝是覆盖上一次的拷贝，不会多出重复条目。

> v1 没有 App 内导入功能（JSON 导入导出在 v1.1 路线图里），只能按上面的方式手动放文件。

### WorkBuddy 配置

| 手柄 | 动作 | WorkBuddy 里的功能 |
|------|------|--------------------|
| 右摇杆 | 鼠标移动 | 移动光标 |
| 左摇杆 | 滚动 | 对话区滚动 |
| L2 / R2 | 滚动 / 鼠标右键 | 滚对话 / 右键菜单 |
| □ / R3 | 鼠标左键 | 点击 |
| ○ | 鼠标右键 | 右键菜单 |
| × | `Delete` | 删字 |
| △ | `Enter` | 发送消息 |
| L1 | `⌘[` | 上一个任务 |
| R1 | `⌘]` | 下一个任务 |
| L3 | `⇧⌘B` | 切换右侧栏 |
| 方向键 ↑ / ↓ | `↑` / `↓` | 列表内上下移动 |
| 方向键 ← / → | 上一个 / 下一个桌面 | 切空间 |
| 触摸板 | 调度中心 | 看所有窗口 |
| Options | 长按 `⌥` | 修饰键 |
| Share | 切换预设 | 换下一套 |
| PS | 未绑定 | — |

### Orca 配置

| 手柄 | 动作 | Orca 里的功能 |
|------|------|---------------|
| 右摇杆 | 鼠标移动 | 移动光标 |
| 左摇杆 | 滚动 | 终端滚动 |
| L2 / R2 | 滚动 / 鼠标右键 | — |
| □ | `Enter` | 执行命令 |
| △ | `Tab` | 补全 |
| ○ / R3 | 鼠标右键 / 左键 | 点击 |
| × | `Delete` | 删字 |
| L1 | `⇧⌘[` | 上一个标签 |
| R1 | 调度中心 | 看所有窗口 |
| L3 | `⌘⌥T` | 新建 agent 标签 |
| 方向键 ↑ / ↓ | `⌘↑` / `⌘↓` | 上一个 / 下一个 worktree |
| 方向键 ← / → | `⇧⌘[` / `⇧⌘]` | 切标签 |
| 触摸板 | `⌘⌥A` | 浮动终端 |
| Options | `⌘E` | 语音输入 |
| PS / Share | 切换预设 | 换下一套 |

两套的差别不在按键本身，而在同一颗键送出的组合：

> ⚠️ 两套配置里都有一条「触摸板 → 调度中心 / 浮动终端」。一旦开启「触摸板当鼠标」，
> 触摸板按键会被接管成**鼠标左键**，这条映射不再生效（否则一次按压会同时触发两个动作）。
> 想保留原来的触摸板映射，就别开触摸板鼠标。

| 位置 | WorkBuddy | Orca |
|------|-----------|------|
| 方向 ↑ ↓ | 纯方向键，列表内挪 | `⌘↑` / `⌘↓`，切 worktree |
| L1 / R1 | `⌘[` `⌘]` 切任务 | `⇧⌘[` `⇧⌘]` 切标签 |
| △ | 回车发送 | Tab 补全 |
| L3 | 切右栏 | 新建 agent 标签 |
| Options | 长按 Option | 语音输入 |
| 触摸板 | 调度中心 | 浮动终端 |

---

## 技术栈

- **语言**：Swift 5.9+ / SwiftUI
- **最低系统**：macOS 13 Ventura
- **推荐系统**：macOS 14 Sonoma（完整 MenuBarExtra 能力）
- **PS4 接入**：`IOKit` / `IOBluetooth` 的 `IOHIDManager` 直接解析蓝牙 HID 报告（vendor `0x054C`，pid `0x09CC`/`0x05C4`/`0x0CE6`）。_注：早期方案计划用 `GameController.framework`，但 macOS 26 上该框架的 PS4 事件流存在 bug，最终改走 IOHIDManager 绕过，详见 `Sources/DS4Mate/Services/HIDControllerService.swift` 顶部注释。_
- **事件合成**：CoreGraphics `CGEvent.post(tap: .cgSessionEventTap)`；触摸板指针走 `.cghidEventTap` 并以 240Hz 独立时钟输出
- **触摸板**：`GET_REPORT(feature 0x02)` 解锁完整报告 → 解析 12bit 坐标（每包 3~4 个时间采样） → 按 touchID 分组区分单指序列 / 多指并行 → 单指走插值 + 速度自适应一阶低通 → 差分合成鼠标位移；**只输出相对位移**，抬指即清空绝对坐标基准（无触摸帧 / touchID 变化 / 瞬时断触三重判定）；双指走手势识别（滚动 / 缩放）（详见 `docs/touchpad-mouse.md`）
- **持久化**：Codable JSON + @AppStorage
- **本地化**：运行时双语词典（`Localization.swift` + `LocalizableStrings.swift`，321 条 × 2 语言）。不用 `.lproj` 是因为构建走手工 bundle 组装，且系统级语言切换要重启进程才生效
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
│   ├── touchpad-mouse.md          # 触摸板当鼠标：原理 / 验证 / 调参 / 限制
│   ├── design-tokens.json         # W3C 标准设计 Token
│   ├── design-system/             # 6 个页面范式
│   ├── decisions/                 # 9 个 ADR + JSON Schema
│   └── adr-index.md
├── Sources/DS4Mate/
│   ├── App/                       # @main / AppState / Localization / 首启调度
│   ├── Models/                    # 数据模型（含快捷键语义表）
│   ├── Services/                  # ControllerService / EventSynthesizer 等
│   ├── Views/                     # SwiftUI 视图（含语言选择页）
│   └── Resources/                 # Info.plist
├── Tests/RunTests.swift           # 211 个冒烟测试（含真机抓包回归）
├── examples/                      # 两套现成配置（workbuddy / orca）
├── tools/hid-probe/               # 独立 HID 探针（排查触摸板数据源，不参与 App 构建）
├── scripts/build.sh               # 一键构建脚本（含词条校验门禁）
├── scripts/check-i18n.py          # 中英词条一致性校验
├── Package.swift                  # SwiftPM 定义
└── build/                         # 编译产物
    ├── DS4Mate                    # 独立可执行（约 1.8MB）
    ├── DS4Mate.app                # .app bundle（可双击运行）
    └── DS4MateTests               # 测试可执行
```

---

## 数据流

```
[PS4 手柄]
  ↓ 蓝牙 (HID)  ← GET_REPORT(0x02) 后从精简 0x01 切到完整 0x11
[IOHIDManager]  ← 直接读 HID 报告（绕过 macOS 26 的 GameController.framework 缺陷）
  ↓ 报告解析（按键 / 摇杆 / 触摸采样）
[ControllerService] ← 持有 [Profile] (active)
  ├─ 按键 / 摇杆 ─→ 查 binding(for: input) ─→ [EventSynthesizer] ─┐
  └─ 触摸采样 ───→ [TouchpadPointerEngine] 240Hz 插值+低通+差分 ─┤
                                                    [TouchpadMouseService] ─┘
  ↓ CGEvent.post / .cghidEventTap
[macOS 输入系统]
  ↓
[前台 App]
```

---

## 已知限制

1. **媒体键未实现**：`Action.mediaKey`（音量加减 / 播放暂停 / 上一首下一首 / 静音）在 v1 里只会往控制台打一行 `mediaKey not implemented`，不会真的发出媒体键事件——macOS 没有公开的媒体键 API，完整实现需走私有 `NSEvent`。绑定这些动作时请改用系统快捷键或键盘模拟替代
2. **触摸板只支持双指，不支持三指手势**：双指滚动 / 捏合缩放已实现（`docs/touchpad-mouse.md`）；三指手势（调度中心、Mission Control）未做
3. **捏合缩放走 `⌘=` / `⌘-` 热键，不是系统 magnify 手势**：macOS 的 magnify 是私有事件类型，CGEvent 层没有公开构造函数，伪造行为跨系统版本不可控。代价是在 Finder 这类把 `⌘=` 绑成「打开」的 App 里可能误触，所以缩放默认不灵敏，也可以在设置里关掉
4. **PS 键在 GCDualShockGamepad 上不可读**：macOS GameController 框架未暴露 PS/Share/Options 按键，v1 通过反射拿 `shareButton`/`optionsButton` 私有路径
5. **未上架 App Store / 无 Apple 开发者证书**：用本机自签（无证书时回退 ad-hoc）；Gatekeeper 首次打开会弹警告，需右键 → 打开
6. **千问语音控制依赖 UI 布局**：通过辅助功能读取千问（Qwen）窗口的按钮，依赖其界面布局与「辅助功能」授权；千问改版或窗口不在当前桌面时可能失效（已做跨桌面切换兜底）。讯飞语音输入同理

---

## 路线图

- v1.0（MVP，已完成）：蓝牙连接 + 多预设管理（全部用户自建）+ 可视化编辑
- v1.1（已完成）：中英双语界面 + 菜单栏显示当前预设名 + 两套示例配置 + 删除单份预设
- v1.2（当前）：触摸板当鼠标（原始 HID 多子帧 + 240Hz 输出 + 抬指即止）+ 双指滚动 / 捏合缩放 + 讯飞语音输入动作
- v1.3：触摸板三指手势 + 摇杆死区与灵敏度调节 + JSON 导入导出 + 反向/互换
- v2.0：多 Profile（同时多套切换）+ Xbox/PS5/Switch Pro 支持 + 宏录制 + USB 有线

---

## 许可

MIT License
