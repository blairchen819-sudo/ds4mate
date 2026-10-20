# DS4Mate 设计规范（Design Spec v1.0）

> 项目代号：DS4Mate
> 平台：macOS 13 Ventura+ / 14 Sonoma+
> 技术栈：Swift 5.9+ · SwiftUI · MenuBarExtra · IOKit / IOHID · CoreBluetooth
> 设计寄存器：**Product Register**（设计服务产品——工具型菜单栏 App）
> 设计三轴刻度：`DESIGN_VARIANCE = 4`（克制的非对称）· `MOTION_INTENSITY = 3`（功能性极简）· `VISUAL_DENSITY = 6`（中密度，配置型 UI）

---

## 0. 设计哲学与品牌声音

**三个品牌声音词**：`专业` · `物理精确` · `静默常驻`

- **专业**：菜单栏常驻型工具，受众是愿意折腾但讨厌低质量软件的玩家。视觉不卖萌，不堆 emoji，不做动效炫耀。参考 Apple 系统设置、Linear、BetterTouchTool 的冷静感。
- **物理精确**：手柄是物理输入设备，UI 必须"看得见手在动"——按键可视化、按下高亮、动作回显，键鼠事件一对一可见映射。
- **静默常驻**：菜单栏图标是产品门面，必须在 22×22pt 限制下保持识别度，常驻时极小、按下/状态变化时才有动作。状态切换≤150ms 一闪即走。

**反词**：`活泼` · `新潮紫粉` · `花哨动效` · `居中大Hero`

---

## 1. 竞品 UI 范式总结

调研 5 款竞品的界面范式后，DS4Mate 的设计策略确定如下。

### 1.1 竞品对照矩阵

| 竞品 | 编辑器范式 | 优点 | 缺点 | DS4Mate 取舍 |
|------|------------|------|------|--------------|
| **ControllerMate** | 拖拽式"积木"块（输入块→逻辑块→输出块） | 表达力极强，可做条件/循环/AppleScript | 画布信息密度高，新手 30 分钟上手不了；UI 老旧（AppKit 原始风） | **不学积木画布**（DS4Mate 不需要复杂逻辑链）。**学其"事件流可视化"理念**：手柄 → 动作的流向是清晰的 |
| **Karabiner-Elements** | Tab + JSON 树形（Simple/Complex Modifications） | 简单修改极快（Popup 选 From→To）；复杂规则有社区生态 | 必须看 JSON 才能用 Complex；初学者不知道 Simple/Complex 区别 | **学其"一键单映射"的 Popup 体验**；**不学其 JSON 模式**（用户原话"想自己改映射玩点花样"——需要 GUI 点击，不需要 JSON） |
| **BetterTouchTool** | 多设备并列（鼠标/触控板/键盘/Settings/预设），每设备独立画布 | 设备维度切换清晰；预设切换非常顺滑 | 单设备画布内容密集，颜色有点过饱和；首次进入不知道从哪开始 | **学其"预设切换"的即时性**；**学其多设备思维**（DS4Mate 未来可能支持多手柄，但 V1 仅 PS4） |
| **Stream Deck（Elgato）** | 三栏：左侧动作库（搜索 + 分类）+ 中间按键网格 + 右侧属性面板 | 拖放动作到按键最直观；搜索 + 分类非常高效；多 Profile 切换无感 | 软件层不是 macOS 原生（早期缺菜单栏图标、缺 Dock 行为）；动作描述有时不够直观 | **主学**：左动作库 + 中键位网格 + 右属性面板。**补救 Stream Deck 缺陷**：原生 MenuBarExtra + 完整 macOS 行为 |
| **Steam Controller 配置** | 大圆按钮可视化点击 + 弹出动作选择器（半径触发、连点、组合键） | **最值得学**：可视化"点哪个键 → 选什么动作"，学习成本接近零；激活器（长按/双击）概念强大 | 大屏触摸优化，桌面看起来略空；菜单嵌套较深 | **主学**：点击手柄上某个键 → 弹出动作选择器 → 立即生效。**不学其大屏留白**（macOS 上紧凑更专业） |

### 1.2 DS4Mate 的核心范式决策

**范式 A：**「点击手柄上的按键 → 右侧出现该键的动作配置 → 点击动作槽位 → 弹出动作选择器 Sheet」
**范式 B：**「左侧动作库 → 拖到中间手柄的某个按键上 → 自动绑定」

**V1 优先 A**（点击触发，符合 macOS HIG；B 作为 Power Feature 加进 toolbar）。原因：A 是 Steam Controller 验证过的零学习成本范式，且 macOS 上拖放需要明确的 hover 反馈，对菜单栏 App 来说工程量偏大。

### 1.3 设计基调（向 152+ 设计系统对齐）

| 设计系统对标 | 取什么 | 避什么 |
|-------------|--------|--------|
| Apple System Settings（macOS 13+）| 原生外观、分组、Section header 大写小标签 | Apple 的过度灰色（DS4Mate 加一点品牌蓝层次） |
| Linear | 紧凑密度、1px 边框、键盘可达 | Linear 的紫色渐变（DS4Mate 用深蓝） |
| BetterTouchTool | 设备/预设双层管理、即时切换 | BTT 的旧版霓虹色 |
| SF Symbols 5（Apple 原生）| 全矢量、统一尺寸、与文本对齐 | emoji 替代图标 |
| Stream Deck 7 | 动作库搜索 + 分类 | 三栏布局宽度（DS4Mate 用紧凑双栏 + 弹出 Sheet） |

---

## 2. Design Tokens（设计系统核心）

### 2.1 主色决策

**推荐主色：深蓝 `Steel Blue 600 = #1E5BAF`（深蓝偏冷，呼应 PS4 蓝但避开蓝紫）**

理由：
1. **避开紫粉**：P0 红线，也是默认靛蓝的 AI 味
2. **避开 `#2563EB` 默认 Tailwind 蓝**：那是另一个 AI 标志
3. **呼应产品语义**：PS4 DualShock 标志色就是深蓝，玩家直觉关联
4. **专业感**：深蓝在 macOS 菜单栏深色模式下识别度极高，且不刺眼
5. **对比度**：在白底 11.2:1、在黑底 7.4:1，远超 WCAG AA（4.5:1）

**备选**：`Graphite Teal 600 = #0F766E`（墨绿，冷静工具风）、`Steel 600 = #475569`（纯中性钢灰，最极简）。

### 2.2 Design Token 定义（CSS 变量形式，SwiftUI 编译时转 DesignConstant）

```css
/* ============================================================
 * A1 - Identity Token（品牌 DNA，变更频率极低）
 * ============================================================ */
:root {
  /* ——— 品牌主色：Steel Blue 600 ——— */
  --brand-50:  #EEF4FC;
  --brand-100: #D6E4F7;
  --brand-200: #A9C5EB;
  --brand-300: #7BA4DE;
  --brand-400: #4A82D0;
  --brand-500: #2A6BC2;   /* 基准色：菜单栏禁用态图标 */
  --brand-600: #1E5BAF;   /* * 主色：CTA、选中、强调 */
  --brand-700: #174887;
  --brand-800: #103562;
  --brand-900: #0A2240;

  /* ——— 中性色：Warm Slate（带轻微蓝调，避开纯灰 AI 感） ——— */
  --neutral-0:   #FFFFFF;
  --neutral-50:  #F8FAFC;
  --neutral-100: #F1F5F9;
  --neutral-200: #E2E8F0;
  --neutral-300: #CBD5E1;
  --neutral-400: #94A3B8;
  --neutral-500: #64748B;
  --neutral-600: #475569;
  --neutral-700: #334155;
  --neutral-800: #1E293B;
  --neutral-900: #0F172A;
  --neutral-950: #020617;
}

/* ============================================================
 * A2 - Structure Token（结构层，布局系统）
 * ============================================================ */
:root {
  /* —— 间距（4px 基准网格，仅允许 4 的倍数） —— */
  --space-0:   0;
  --space-1:   4px;     /* 图标↔文字 */
  --space-2:   8px;     /* 同一组元素内 */
  --space-3:  12px;     /* 按钮内边距、列表项高 */
  --space-4:  16px;     /* 卡片内边距、节区间距 */
  --space-5:  20px;     /* 模块间距 */
  --space-6:  24px;     /* 大模块间距 */
  --space-8:  32px;     /* Section 间距 */
  --space-10: 40px;
  --space-12: 48px;
  --space-16: 64px;     /* 仅 Hero / 主窗口标题 */

  /* —— 圆角（macOS HIG + 避免过度圆滑） —— */
  --radius-xs:   4px;    /* Tag、Pill 内 */
  --radius-sm:   6px;    /* 按钮、输入框 */
  --radius-md:   8px;    /* 卡片、Sheet */
  --radius-lg:  12px;    /* 主窗口 */
  --radius-xl:  16px;    /* 弹窗 */
  --radius-pill: 9999px; /* 状态徽章、Toggle */

  /* —— 阴影（macOS 上极克制，1px 边框优于阴影） —— */
  --shadow-none: none;
  --shadow-xs:  0 1px 2px rgba(15, 23, 42, 0.05);
  --shadow-sm:  0 1px 3px rgba(15, 23, 42, 0.08), 0 1px 2px rgba(15, 23, 42, 0.04);
  --shadow-md:  0 4px 12px rgba(15, 23, 42, 0.08), 0 2px 4px rgba(15, 23, 42, 0.04);
  --shadow-lg:  0 12px 32px rgba(15, 23, 42, 0.10), 0 4px 8px rgba(15, 23, 42, 0.06);

  /* —— 动效 —— */
  --motion-instant:  80ms;   /* 按钮按下 */
  --motion-fast:    150ms;   /* hover、状态切换 */
  --motion-base:    220ms;   /* 进入/退出 */
  --motion-slow:    360ms;   /* Sheet、模态 */
  --ease-standard:  cubic-bezier(0.2, 0, 0, 1);
  --ease-emphasized: cubic-bezier(0.32, 0.72, 0, 1);
}

/* ============================================================
 * A2 - Semantic Token（语义层，自动派生）
 * ============================================================ */
:root {
  --color-success: #15803D;
  --color-success-bg: #DCFCE7;
  --color-success-fg: #14532D;

  --color-warning: #B45309;
  --color-warning-bg: #FEF3C7;
  --color-warning-fg: #78350F;

  --color-danger:  #B91C1C;
  --color-danger-bg: #FEE2E2;
  --color-danger-fg: #7F1D1D;

  --color-info:    var(--brand-600);
  --color-info-bg: var(--brand-50);
  --color-info-fg: var(--brand-800);
}

/* ============================================================
 * B - Slot Token（语义化角色别名）
 * ============================================================ */
:root {
  /* Surface */
  --bg-app:        var(--neutral-50);    /* 主窗口背景 */
  --bg-window:     var(--neutral-0);     /* 卡片表面 */
  --bg-sunken:     var(--neutral-100);   /* 输入框、凹陷面板 */
  --bg-overlay:    rgba(15, 23, 42, 0.45); /* Sheet 背景蒙版 */
  --bg-menubar:    transparent;          /* 菜单栏下拉 */
  --bg-hover:      rgba(30, 91, 175, 0.08);
  --bg-selected:   var(--brand-50);
  --bg-key-down:   var(--brand-100);     /* 手柄按键按下高亮 */

  /* Foreground */
  --fg-primary:    var(--neutral-900);    /* 主文本 */
  --fg-secondary:  var(--neutral-600);    /* 副文本 */
  --fg-tertiary:   var(--neutral-500);    /* 元数据、标签 */
  --fg-disabled:   var(--neutral-400);    /* 禁用 */
  --fg-on-brand:   var(--neutral-0);      /* 主色背景上的文字 */
  --fg-brand:      var(--brand-600);      /* 主色文字 */
  --fg-inverse:    var(--neutral-0);      /* 反色 */

  /* Border */
  --border-default:  var(--neutral-200);
  --border-strong:   var(--neutral-300);
  --border-focus:    var(--brand-500);
  --border-subtle:   var(--neutral-100);  /* 内部行分隔 */

  /* Focus ring（无障碍必须） */
  --focus-ring: 0 0 0 3px rgba(30, 91, 175, 0.30);
  --focus-ring-tight: 0 0 0 2px rgba(30, 91, 175, 0.45);
}

/* ============================================================
 * macOS Dark Mode（菜单栏 App 必须双模式适配）
 * ============================================================ */
:root[data-theme="dark"] {
  --bg-app:        #0F172A;     /* 深蓝灰底，与浅色一致冷调 */
  --bg-window:     #1E293B;
  --bg-sunken:     #0B1220;
  --bg-overlay:    rgba(0, 0, 0, 0.55);
  --bg-hover:      rgba(255, 255, 255, 0.06);
  --bg-selected:   rgba(30, 91, 175, 0.20);
  --bg-key-down:   rgba(30, 91, 175, 0.35);

  --fg-primary:    #F1F5F9;
  --fg-secondary:  #CBD5E1;
  --fg-tertiary:   #94A3B8;
  --fg-disabled:   #475569;

  --border-default: #334155;
  --border-strong:  #475569;
  --border-subtle:  #1E293B;

  --focus-ring: 0 0 0 3px rgba(122, 164, 222, 0.45);
}
```

### 2.3 字体系统

**字体栈**：使用 macOS 系统字体 SF Pro（SwiftUI `.system` 自动获得）+ 中文 fallback PingFang SC。

```css
--font-display:  'SF Pro Display', 'SF Pro', 'PingFang SC', system-ui, sans-serif;
--font-body:     'SF Pro Text',    'SF Pro', 'PingFang SC', system-ui, sans-serif;
--font-mono:     'SF Mono',        'Menlo', monospace;   /* 仅用于键码、坐标显示 */
```

**字号层级**（紧凑工具型 App，最多 7 级）：

| Token | 实际值 | 用途 | 字重 |
|-------|--------|------|------|
| `--text-xs`  | 11px | 标签、徽章、菜单栏状态 | 510 / ALL CAPS 0.06em |
| `--text-sm`  | 12px | 辅助说明、坐标 | 400 |
| `--text-base`| 13px | 主窗口正文 | 400 |
| `--text-md`  | 14px | 列表项 | 400 |
| `--text-lg`  | 16px | 节区标题、按钮文字 | 510 |
| `--text-xl`  | 18px | 主窗口一级标题 | 590 / -0.01em |
| `--text-2xl` | 22px | 弹窗标题 | 590 / -0.01em |
| `--text-3xl` | 28px | Onboarding 标题 | 590 / -0.02em |

> macOS 13+ 系统设置字号基准 13px，DS4Mate 跟随 HIG。

### 2.4 图标系统（**SF Symbols**）

- **库**：SF Symbols 5（macOS 14 Sonoma+ 含 5000+ 图标，含游戏控制器按钮）
- **尺寸**：14px（菜单栏，常态）/ 16px（行内）/ 20px（按钮内）/ 24px（独立）
- **字重**：与文本字重联动（SwiftUI `imageScale` + `fontWeight`）
- **渲染模式**：`symbolRenderingMode(.hierarchical)`（统一深色，hover/active 时加深）优于 `.multicolor`（多彩容易喧宾夺主）
- **绝对禁止**：emoji 作为功能图标（详见 §7 自查清单）

完整 SF Symbols 选型见 §5。

---

## 3. 页面清单（6 个核心页面 + ASCII 草图）

### 3.1 主菜单（MenuBarExtra 下拉）

**路由**：菜单栏点击图标 → popover
**尺寸**：约 280pt 宽 × 自适应高（macOS MenuBarExtra 默认）
**触发**：单击菜单栏图标

**核心组件**：
- 状态指示器（图标 + 文字）：`已连接/未连接/已禁用`
- 启停 Toggle（Switch）
- Profile 切换（Submenu 或 Section）
- 动作行：`打开编辑器`、`设置`、`关于`
- 退出

**ASCII 草图**：

```
┌──────────────────────────────────────┐
│ ┌──┐  DS4Mate            [Gear] Settings │
│ │[V] │  DualShock 4 已连接    ⌘E 编辑 │
│ └──┘  [■■■■■■■■] 100%                │
├──────────────────────────────────────┤
│ ▶  启用映射            [●━━○] ON    │  ← Toggle
├──────────────────────────────────────┤
│ 当前 Profile                       ▸ │  ← Submenu
│   ● 默认                                    │
│   ○ 媒体控制                                │
│   ○ 演示遥控                                │
│   ────                                     │
│   ○ 编辑 Profile…                           │
├──────────────────────────────────────┤
│   [Bt] 重新连接蓝牙          ⌘R       │
│   [Edit] 打开编辑器           ⌘E       │
│   [Gear] 设置…                ⌘,       │
│   [?] 使用帮助                            │
├──────────────────────────────────────┤
│ 退出 DS4Mate                  ⌘Q     │
└──────────────────────────────────────┘
```

**关键设计**：
- 菜单栏图标（22×22pt）：连接状态用 SF Symbol `gamecontroller.fill`（已连）/ `gamecontroller`（未连）/ `gamecontroller.slash`（禁用）
- 不显示 emoji（"" 等位置用 SF Symbol `antenna.radiowaves.left.and.right` —— 此处为反例文字说明，实际 UI 必须用 SF Symbol）
- 退出永远在最底部，独立一栏，红字危险色

### 3.2 主窗口：可视化键位编辑器（核心页）

**路由**：菜单栏 → 打开编辑器
**尺寸**：720 × 520 pt（macOS 标准 settings 窗口尺寸偏大）
**模式**：NSWindow（非 Sheet，更符合 macOS 工具 App 习惯）

**布局**：双栏 `HSplitView`

```
┌────────────────────────────┬─────────────────────────────┐
│  [Profile: 默认 ▾]   [+]  │  选中键：△ Y (Triangle)      │
│                            │  ───────────────             │
│                            │  当前动作：                  │
│      ┌──────────────┐      │    [Mouse·中键单击]         │
│      │              │      │    [⇧ Shift]                │
│      │   PS4 SVG    │      │                             │
│      │   按键可点   │      │  ───────────────             │
│      │   悬停高亮   │      │  触发方式：单击 ▾           │
│      │              │      │  连点间隔：— ms             │
│      └──────────────┘      │  长按延迟：500 ms           │
│                            │                             │
│  已映射：8 / 14 键         │  [ 更换动作 ]  [ 清除 ]      │
├────────────────────────────┴─────────────────────────────┤
│ 工具栏：[+ 新增] [↶ 撤销] [↷ 重做] [Save 保存] [⇪ 导出]│
└──────────────────────────────────────────────────────────┘
```

**左栏**（手柄可视化区，380pt）：
- **手柄组件**：PS4 DualShock 4 实物 SVG（程序化绘制，不引位图），按真实比例，灰底
- **按键可点击/可悬停**：
  - 默认态：`--bg-window` 背景，1px `--border-default` 边框
  - 悬停：边框变 `--brand-400`，120ms 过渡
  - 选中（左侧高亮）：背景 `--bg-selected`，边框 `--brand-600`，左侧加 2px `--brand-600` 色条
  - 按下回显（实时）：当手柄按键真的被按下，背景闪 `--bg-key-down` 150ms 后回弹
- **按键标识**：在 SVG 内嵌入 SF Symbol（圆/三角/方/叉/L1/R1 等）

**右栏**（动作配置区，340pt）：
- 当前选中的按键名称 + SF Symbol
- 动作槽位列表（可叠加：单击、长按、双击 → 不同动作）
- 触发方式选择器：单击 / 双击 / 长按 / 按住
- 更换动作按钮 → 打开动作选择器 Sheet（§3.3）

**底部工具栏**：
- `+ 新增键映射`：进入"自定义虚拟键"模式（Power User）
- `↶ 撤销` / `↷ 重做`：栈深度 20
- `Save 保存`：脏数据时高亮 `--brand-600`；已保存时灰化

### 3.3 动作选择器 Sheet

**路由**：编辑器右栏 → 更换动作按钮
**尺寸**：560 × 480 pt macOS Sheet

```
┌──────────────────────────────────────────────────┐
│  选择动作                                     [X] │
│  [Q] [搜索：鼠标、键盘、媒体…         ]         │
├──────────────────────────────────────────────────┤
│ [ 鼠标 4 ]  [ 键盘 8 ]  [ 系统 3 ]  [ 媒体 5 ]   │
│                                                  │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
│  │  Mo   │  │  Mo   │  │  Mo   │  │  Mo   │         │
│  │ 左键  │  │ 右键  │  │ 中键  │  │ 滚轮↑│         │
│  │ 单击  │  │ 单击  │  │ 单击  │  │ 上滚 │         │
│  └──────┘  └──────┘  └──────┘  └──────┘         │
│                                                  │
│  ── 最近使用 ─────────────────────               │
│  [Mo·左键]  [⌘C]  [⏯ Play/Pause]  [Esc]  [Spc] │
└──────────────────────────────────────────────────┘
```

**核心组件**：
- **搜索框**：自动 focus，模糊匹配动作名 + 别名
- **分类标签**：横向 Picker（SegmentedControl 风格），4 类默认（鼠标/键盘/系统/媒体）
- **动作卡片**：4 列网格，每张卡 = `SF Symbol + 动作名 + 一句话说明`
- **最近使用**：基于 LRU，最多 5 个，跨 Profile 不共享

**动作卡片规范**：
- 尺寸：120 × 80 pt
- 内容：SF Symbol（24px 主色）+ 中文动作名（13px 510 字重）+ 英文别名（11px tertiary）
- 默认：白底 + 1px `--border-default`
- Hover：边框变 `--brand-400`，背景 `--bg-hover`
- Selected（多选时）：边框 `--brand-600`，背景 `--bg-selected`，左上角 [V] 标记
- 选中即关闭 Sheet 并应用

### 3.4 预设管理窗口

**路由**：菜单栏 → 当前 Profile → 编辑 Profile…
**尺寸**：600 × 400 pt

```
┌──────────────────────────────────────────────────┐
│  预设管理                              [X]       │
├──────────────────────────────────────────────────┤
│ ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│ │  [V] 默认  │  │ 媒体控制 │  │ 演示遥控 │  [+ 新建] │
│ │          │  │          │  │          │          │
│ │ · 左摇杆 │  │ · 媒体键 │  │ · 翻页键 │          │
│ │   →鼠标  │  │   →媒体 │  │   →方向 │          │
│ │ · [X] →Enter│  │ · 音量+− │  │ · 黑屏  │          │
│ │          │  │          │  │          │          │
│ │ [编辑]   │  │ [编辑]   │  │ [编辑]   │          │
│ └──────────┘  └──────────┘  └──────────┘          │
├──────────────────────────────────────────────────┤
│  导入 Profile…           导出当前 Profile…        │
└──────────────────────────────────────────────────┘
```

**核心组件**：预设卡片（3 列 + "+ 新建"），每卡显示映射摘要、Edit 按钮、激活勾选。

### 3.5 设置窗口

**路由**：菜单栏 → 设置（⌘,）
**尺寸**：640 × 480 pt（macOS 标准 Settings 风格）

**结构**：左侧 Sidebar（macOS Settings 风格）+ 右侧 Detail

```
┌──────────────┬─────────────────────────────────────┐
│              │  [Gear] 输入                              │
│  输入        │  ───────────                         │
│  显示        │  鼠标灵敏度    [━━━━━○────]  中       │
│  权限        │  摇杆死区      [━━━○──────]  15%     │
│  关于        │                                     │
│              │  [ ] 启用按键回显（屏幕显示按下键）     │
│              │  [ ] 按住手柄 SHARE 键暂停映射         │
│              │                                     │
│              │  快捷键                              │
│              │  ───────────                         │
│              │  切换启用：  ⌃⌥ Space                │
│              │  切换 Profile：⌃⌥ P                  │
└──────────────┴─────────────────────────────────────┘
```

**侧边栏 4 项**：输入 / 显示 / 权限 / 关于
- **输入**：死区、灵敏度、回显、快捷键
- **显示**：菜单栏图标样式（详见 §5.1）、电池百分比显示
- **权限**：Accessibility（打开系统设置深链）、Bluetooth（系统设置深链）、Input Monitoring；状态用色点 ●○ 指示
- **关于**：版本号、检查更新、致谢

### 3.6 首次启动引导（Onboarding，4 步）

**触发**：V1 首次启动（`~/Library/Application Support/DS4Mate/onboarded.flag` 不存在）
**形式**：多步 Sheet，非全屏窗口（macOS 标准）
**进度指示**：顶部进度条（4 段）+ 步骤标题 + 上一步/下一步

**步骤 1：欢迎**
```
┌──────────────────────────────────────────────┐
│ ▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░  1/4          │
│                                              │
│              [手柄 SVG 插画]                  │
│                                              │
│         把 PS4 手柄变成 Mac 鼠标              │
│                                              │
│  DS4Mate 通过蓝牙连接你的 DualShock 4，     │
│  把按键和摇杆映射成 macOS 的鼠标和键盘       │
│  事件。                                       │
│                                              │
│              [开始设置 →]                     │
└──────────────────────────────────────────────┘
```

**步骤 2：Accessibility 权限申请**
```
┌──────────────────────────────────────────────┐
│ ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░  2/4           │
│                                              │
│         [Shield SF Symbol 插画]              │
│         授权 macOS 辅助功能                   │
│                                              │
│  macOS 要求应用获得"辅助功能"权限           │
│  才能模拟键盘和鼠标事件。                     │
│                                              │
│  点击下方按钮，系统会自动打开                 │
│  「隐私与安全性 → 辅助功能」                  │
│                                              │
│  1. 打开系统设置                             │
│  2. 找到 DS4Mate 并打开开关                  │
│  3. 返回此窗口继续                           │
│                                              │
│       [打开系统设置]   [已手动开启]           │
└──────────────────────────────────────────────┘
```

**步骤 3：蓝牙配对手柄**
```
┌──────────────────────────────────────────────┐
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  3/4            │
│                                              │
│    [蓝牙动画 SF Symbol + 文字状态]            │
│                                              │
│         连接你的 DualShock 4                 │
│                                              │
│  ● 长按手柄 SHARE 键 + PS 键 3 秒            │
│    直到顶部灯条快速闪烁                       │
│                                              │
│  ● 点击下方按钮开始扫描                       │
│                                              │
│  ── 检测到的设备 ──                           │
│  ◌ Wireless Controller           [配对]      │
│  ◌ Wireless Controller (2)       [配对]      │
│                                              │
│       [重新扫描]              [下一步 →]     │
└──────────────────────────────────────────────┘
```

**步骤 4：试玩默认映射**
```
┌──────────────────────────────────────────────┐
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  4/4        │
│                                              │
│         [Target SF Symbol + 计数器]           │
│         试一下默认映射                       │
│                                              │
│  按下手柄按键测试映射是否生效                 │
│                                              │
│  [V] 左摇杆推动鼠标（已检测 3 次）              │
│  [V] △ 已映射 Y 键（已检测 1 次）              │
│  ◯ ○ 已映射 ← 键（未检测）                   │
│                                              │
│  ────                                       │
│  [V] 全部完成！                                │
│  [打开编辑器 →]                               │
│                                              │
└──────────────────────────────────────────────┘
```

---

## 4. 核心交互流程

### 4.1 首启动流（Onboarding）

```
[下载 dmg]
   ↓
[拖入 Applications]
   ↓
[双击启动] → 检测 onboarded.flag 不存在
   ↓
[Onboarding Sheet 自动弹出，4 步]
   ├─ 1. 欢迎介绍
   ├─ 2. 申请 Accessibility 权限
   │     ↓
   │     [打开系统设置深链: x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility]
   │     ↓
   │     [用户开启] → [点击"已手动开启"] → [检测 AXIsProcessTrusted] → 通过则进入下一步
   ├─ 3. 蓝牙配对 (CoreBluetooth scan)
   │     ↓
   │     [显示附近 DualShock 设备] → [用户点击配对] → [写入 onboarded.flag]
   └─ 4. 试玩 + 实时检测
         ↓
         [用户按键 → 计数器+1]
         ↓
         [3 个核心键均检测 → "完成" → [打开编辑器]]
```

**关键设计**：
- 任何一步都允许"跳过"（最小 MVP 不阻塞用户）
- 每步的"下一步"按钮在条件未满足时灰化（如第 3 步未配对时下一步灰化）
- 进度条始终可见（满足 macOS 标准多步 Sheet 预期）

### 4.2 改一个键的流程

```
[菜单栏点击 DS4Mate 图标]
   ↓
[菜单栏下拉] → 点击「打开编辑器」⌘E
   ↓
[主窗口弹出，默认聚焦到 "△" 键]
   ↓
[用户点击手柄上的 ⬜ 方块键]
   ↓
[右栏切换到该键的配置，显示当前动作]
   ↓
[用户点击「更换动作」按钮]
   ↓
[动作选择器 Sheet 从底部弹出]
   ↓
[搜索框自动 focus]
   ↓
[用户点击"鼠标左键"卡片]
   ↓
[Sheet 关闭，动作立即生效，主窗口"已修改"角标亮起]
   ↓
[用户 ⌘S 保存 / 或自动 5 秒后保存]
```

**关键交互细节**：
- 手柄按键的真实按下事件会触发"回显高亮"——左栏按键闪 `--bg-key-down` 颜色（150ms 一闪），让用户看到"我按的确实是这个键"
- 动作切换有"未保存"状态指示（红点 + 文案"已修改，未保存"），但 5 秒静默期后自动保存并 toast 提示

### 4.3 Profile 切换流程

```
[菜单栏点击 DS4Mate 图标]
   ↓
[菜单栏下拉 → 当前 Profile → Submenu]
   ↓
[点击"媒体控制"]
   ↓
[立即生效，无需确认，无 toast，无模态]
   ↓
[菜单栏图标短暂闪一下 brand 颜色 150ms，作为唯一反馈]
```

**关键设计**：
- Profile 切换是"原子操作"——用户已经在菜单栏上下文，无须再确认
- 唯一的反馈是菜单栏图标的 150ms 颜色脉冲，告知"切换已生效"
- 若 5 秒内有按键输入，则不显示任何 toast，避免打扰正在使用的游戏

---

## 5. SF Symbols 选型清单

### 5.1 菜单栏图标（MenuBarExtra）

**主图标**（常驻，根据状态切换）：
| 状态 | SF Symbol 名 | 渲染 |
|------|--------------|------|
| 已连接 + 启用 | `gamecontroller.fill` | `.hierarchical` 蓝色 |
| 已连接 + 禁用 | `gamecontroller` | `.monochrome` 中性灰 |
| 未连接 | `gamecontroller.slash` | `.monochrome` 中性灰 |
| 错误/权限丢失 | `exclamationmark.triangle.fill` | 黄色（warning 颜色） |

**备选候选**（更"DS4Mate 专属"）：
- `dot.radiowaves.left.and.right`（蓝牙感强，但语义不明确为手柄）
- `rectangle.dashed.badge.record`（录制感，不合适）
- **推荐主选**：`gamecontroller.fill`（macOS 14+ SF Symbols 5 新增游戏控制器分类，识别度最高）

**尺寸**：菜单栏模板图标准 22×22pt（含 retina 资源 @1x/@2x/@3x），SwiftUI 中用 `.imageScale(.small)` + font caption 锁 14pt 等效。

### 5.2 主窗口工具栏图标

| 功能 | SF Symbol | 备注 |
|------|-----------|------|
| 新增按键映射 | `plus` | 标准 macOS 工具栏图标 |
| 撤销 | `arrow.uturn.backward` | SF Symbols 5 新增 |
| 重做 | `arrow.uturn.forward` | |
| 保存 | `tray.and.arrow.down` | 含未保存红点 `circle.fill` |
| 删除 | `trash` | |
| 搜索 | `magnifyingglass` | |
| 重置 | `arrow.counterclockwise` | |
| 导出 | `square.and.arrow.up` | |
| 导入 | `square.and.arrow.down` | |

### 5.3 类别 / Section 图标

| 类别 | SF Symbol |
|------|-----------|
| 鼠标 | `computermouse` |
| 键盘 | `keyboard` |
| 系统命令 | `gearshape.2` |
| 媒体 | `speaker.wave.2` |
| 自定义 | `wand.and.stars` |
| 应用启动 | `app.badge.checkmark` |

### 5.4 每个动作的 SF Symbol（V1 完整动作库 28 个）

| 动作 | SF Symbol | 渲染模式 |
|------|-----------|---------|
| **鼠标类（9）** | | |
| 左键单击 | `computermouse` | 单色 |
| 右键单击 | `computermouse.fill`（+ 右键 context 角标） | 单色 |
| 中键单击 | `computermouse`（+ 中间小圆点）| 单色 |
| 滚轮上 | `arrow.up` | 单色 |
| 滚轮下 | `arrow.down` | 单色 |
| 滚轮左 | `arrow.left` | 单色 |
| 滚轮右 | `arrow.right` | 单色 |
| 双击 | `rectangle.on.rectangle` | 单色 |
| 拖拽开始 | `hand.point.up.left.fill` | 单色 |
| **键盘类（10）** | | |
| Enter | `return` | 单色 |
| Esc | `escape` | 单色 |
| Tab | `arrow.right.to.line.alt` | 单色 |
| Space | `space` | 单色 |
| Backspace | `delete.left` | 单色 |
| ↑↓←→ | `arrow.up/down/left/right` | 单色 |
| ⌘ C/V/X | `doc.on.doc` / `doc.on.clipboard` | 单色 |
| 组合键 | `command` + `option` + `control` 复合 | 多色 |
| **系统类（5）** | | |
| 截屏 | `camera.aperture` | 单色 |
| 调度中心 | `rectangle.3.group` | 单色 |
| 锁定屏幕 | `lock.fill` | 单色 |
| 退出应用 | `power` | 单色 |
| 显示桌面 | `menubar.dock.rectangle` | 单色 |
| **媒体类（4）** | | |
| 播放/暂停 | `playpause.fill` | 多色（蓝绿） |
| 上一曲 | `backward.fill` | 单色 |
| 下一曲 | `forward.fill` | 单色 |
| 静音 | `speaker.slash.fill` | 单色 |

> V1 至少 28 个动作覆盖 4 大类。SF Symbols 5 含 5000+ 图标，含游戏控制器按钮，新符号（`return`、`escape`、`delete.left`、`space`、`playpause.fill`、`speaker.slash.fill`）均为 SF Symbols 5 新增，macOS 14+ 全部支持。
> **回退策略**：macOS 13 系统图标不全时用相邻符号 + 自定义 asset 兜底。

### 5.5 状态 / 反馈图标

| 用途 | SF Symbol |
|------|-----------|
| 成功 | `checkmark.circle.fill`（绿色） |
| 失败 | `xmark.circle.fill`（红色） |
| 警告 | `exclamationmark.triangle.fill`（黄色） |
| 信息 | `info.circle.fill`（蓝色） |
| 蓝牙 | `personalhotspot` 或 `bolt.horizontal.circle` |
| 已配对 | `checkmark` |
| 搜索 | `magnifyingglass` |
| 关闭 | `xmark` |
| 设置 | `gearshape` |
| 权限申请 | `lock.shield` |
| 重连中 | `arrow.triangle.2.circlepath`（带 SF Symbol 动画 `.symbolEffect(.rotate)`） |

---

## 6. 布局原则

### 6.1 栅格系统

- **主窗口**：12 列网格，列宽 50pt，沟槽 16pt，最大宽度 720pt
- **主窗口边距**：左右各 24pt，上下各 20pt
- **动作选择器 Sheet**：8 列网格，卡片宽度 120pt，沟槽 12pt
- **菜单栏下拉**：单列，宽 280pt，高自适应

### 6.2 Section 节奏

| 区域 | 间距 |
|------|------|
| 主窗口 Section 之间 | 32pt（`--space-8`） |
| 卡片内边距 | 16pt（`--space-4`） |
| 表单字段间距 | 12pt（`--space-3`） |
| 列表项垂直间距 | 8pt（`--space-2`） |
| 工具栏 vs 内容 | 16pt（`--space-4`） |

### 6.3 响应式（macOS 多窗口尺寸）

主窗口支持用户拖拽调整，最小 600 × 420pt，推荐 720 × 520pt，最大 900 × 700pt。

- **< 700pt 宽**：右栏自动收起为底部 Sheet（点击键 → Sheet 弹出）
- **≥ 700pt**：双栏布局（默认）
- **900pt+**：手柄 SVG 放大至 1.2x

---

## 7. 深度与层级

### 7.1 三级层级（macOS 风格极简阴影）

| 层级 | 用途 | 实现 |
|------|------|------|
| `elev-flat` | 主窗口背景、菜单栏下拉 | 无阴影，无边框 |
| `elev-ring` | 卡片、Sheet、动作选择器项 | 1px `--border-default` |
| `elev-raised` | Sheet 浮层、Tooltip、菜单栏下拉 | `--shadow-md` + 1px 内边框 |

> **核心原则**：macOS 上"边框 + 极轻阴影"远胜于"大模糊阴影"。禁用任何 `backdrop-blur > 8px`（除非做真正的毛玻璃效果如菜单栏下拉）。

### 7.2 深色模式层级（亮度递进而非阴影）

```
背景（最暗） #0F172A
   ↓
表面     #1E293B
   ↓
悬停     #334155（叠加 rgba(255,255,255,0.06)）
   ↓
选中     #475569
   ↓
文本（最亮）#F1F5F9
```

---

## 8. Do's and Don'ts

### [V] 必须做

1. 所有颜色通过 Design Token 引用，零硬编码 hex
2. 所有图标使用 SF Symbols，零 emoji（除 UGC 内容外）
3. 主色（Steel Blue 600）每屏 ≤ 2 处强调使用
4. 按钮、输入框、所有可点击元素必须有 `:focus-visible` 焦点环
5. 键盘可达：Tab 顺序合理，所有菜单项有快捷键
6. 手柄按键的真实按下必须 UI 回显（视觉反馈建立物理直觉）
7. 状态切换 ≤ 150ms，过渡 220ms，Sheet 进退 360ms
8. 遵守 macOS HIG：菜单栏左对齐、`Settings` 命名（不用"Preferences"）、`Quit` 在最后
9. 双模式（浅色/深色）适配，菜单栏图标在两种模式下都识别度足够
10. 文案具体：`重新连接蓝牙` 不写 `重连`，`更换动作` 不写 `修改`

### [X] 严禁做

1. [X] 紫色 → 粉色渐变（`#7C3AED → #EC4899` 及变体）—— P0 红线
2. [X] emoji 作为功能图标（`` `` `` 等）—— P0 红线
3. [X] 千篇一律 Hero（居中大标题 + 副标题 + 抽象 3D 图形）—— 主窗口没有 Hero，是工具视图
4. [X] 空洞占位文案：`"Welcome to DS4Mate"` / `"Let's get started"` / `"Lorem ipsum"`—— 主窗口首屏是手柄编辑器，不是欢迎页
5. [X] 硬编码 hex：`#1E5BAF` 不能直接写在按钮上，必须 `var(--brand-600)`
6. [X] 渐变文字：`background-clip: text` + 渐变背景——macOS HIG 禁用
7. [X] 默认毛玻璃（`backdrop-blur > 12px` + 半透明）—— 菜单栏下拉除外，且只用 `material(.popover)`
8. [X] 侧条纹彩色边框：`border-left: 3px solid var(--accent)` —— AI 标志，禁止
9. [X] 默认靛蓝 `#6366F1` —— AI 模板标志
10. [X] 圆角卡片+彩色左边框 —— AI 标志，详见 §10 错误模板
11. [X] 编号 section 标记（`01 · 关于 / 02 · 流程 / 03 · 定价`）—— AI 脚手架
12. [X] 每节都有小型大写追踪标签 —— AI 语法

### 错误模板警告（立即重写）

```swift
// [X] AI 味——圆角卡片 + 彩色左边框
VStack(alignment: .leading) {
    Text("Mapping")
    Text("...")
}
.padding()
.background(.white)
.cornerRadius(12)
.overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.2)))
.overlay(alignment: .leading) {
    Rectangle().fill(Color.blue).frame(width: 3)  // [X]
}

// [V] DS4Mate 风格——统一边框，hover 时变色
VStack(alignment: .leading) {
    Text("Mapping")
    Text("...")
}
.padding(.horizontal, 16)
.padding(.vertical, 12)
.background(.window)  // var(--bg-window)
.overlay(RoundedRectangle(cornerRadius: 8).stroke(.border))  // var(--border-default)
.onHover { hovering in
    withAnimation(.fast) {
        // hover 时：边框变 var(--brand-400)
    }
}
```

---

## 9. 响应式与多窗口

### 9.1 窗口类型清单

| 窗口 | 类型 | 尺寸 | 行为 |
|------|------|------|------|
| 主窗口（编辑器） | NSWindow | 720×520pt 默认，可调 | 单例，关闭 = 隐藏不退出 |
| 动作选择器 | Sheet | 560×480pt | 模态，关闭 = 焦点回主窗口 |
| 预设管理 | NSWindow | 600×400pt | 多实例允许 |
| 设置 | NSWindow（标准 macOS Settings 协议）| 640×480pt | 单例，⌘, |
| Onboarding | Sheet | 540×440pt | 模态，仅首次启动 |

### 9.2 多显示器

- 主窗口位置跟随用户最后关闭位置（NSWindow `setFrameAutosaveName`）
- 菜单栏图标在每个显示器顶部都可见（macOS 标准）
- 不强制居中屏幕（macOS 系统设置也不居中）

### 9.3 菜单栏图标在 macOS 13/14 不同行为

- macOS 13：MenuBarExtra 默认会被系统隐藏（空间不足时）→ 提供"始终显示"开关在设置中
- macOS 14+：MenuBarExtra 默认始终显示 → 但仍提供 Settings 中的开关（用户偏好）

---

## 10. 组件状态矩阵

### 10.1 按钮（5 态）

| 状态 | 视觉 |
|------|------|
| Default | bg `--brand-600`，text `--fg-on-brand`，radius `--radius-sm`，padding 10×16 |
| Hover | bg `--brand-700`（`color-mix` 派生） |
| Active/Pressed | bg `--brand-800`，scale 0.98 |
| Focus | `var(--focus-ring)` 3px 半透明环 |
| Disabled | opacity 0.4，cursor: default，不可点击 |
| Loading | 内嵌 Spinner + 文案"保存中..." |

### 10.2 输入框（5 态）

| 状态 | 视觉 |
|------|------|
| Default | bg `--bg-sunken`，border `--border-default`，padding 8×12 |
| Focus | border `--border-focus`，外加 `var(--focus-ring)` |
| Error | border `--color-danger`，helper text 红色 |
| Disabled | bg `--neutral-100`，text `--fg-disabled` |
| Read-only | 无 border，bg 透明，下划线样式 |

### 10.3 手柄按键（手柄组件专用，6 态）

| 状态 | 视觉 |
|------|------|
| Default | bg `--bg-window`，border 1px `--border-default` |
| Hover | border `--brand-400` |
| Selected | bg `--bg-selected`，border 2px `--brand-600`，左侧 2px 条 |
| Pressed (回显) | bg `--bg-key-down`（150ms 闪） |
| Disabled | opacity 0.3 |
| 未映射 | 加 SF Symbol `questionmark` 角标（灰） |

### 10.4 菜单栏图标（4 态）

| 状态 | SF Symbol | 颜色 |
|------|-----------|------|
| 已连接 + 启用 | `gamecontroller.fill` | `--brand-600` |
| 已连接 + 禁用 | `gamecontroller` | `--neutral-500` |
| 未连接 | `gamecontroller.slash` | `--neutral-500` |
| 错误 | `exclamationmark.triangle.fill` | `--color-warning` |

### 10.5 动作选择器 Sheet（5 态）

| 状态 | 视觉 |
|------|------|
| Empty（首次打开） | 显示分类 + 提示"从下方选择或搜索" |
| Searching | 搜索框聚焦，分类淡出仅保留顶部 |
| Populated | 4 列网格，分类标签激活 |
| No results | 居中插画 + "未找到'xxx'，试试其他关键词" |
| Selected | 卡片勾选，0.3s 后自动关闭 Sheet |

### 10.6 数据加载与错误

- 加载中：左栏手柄位置显示 Skeleton（半透明灰色轮廓 + 微光扫过 1.2s 循环）
- 蓝牙扫描中：设备列表逐项淡入（stagger 80ms）
- 错误：全屏插画（手柄 + 错误 SF Symbol）+ 具体错误信息 + 重试按钮

---

## 11. 可访问性（a11y）

| 项 | 实现 |
|----|------|
| 颜色对比度 | 主文本 `--neutral-900` on `--neutral-0` = 16.8:1；副文本 `--neutral-600` on white = 5.7:1；远高于 WCAG AA 4.5:1 |
| 焦点可见性 | 所有可聚焦元素有 `focus-visible` 焦点环，macOS 键盘导航完整 |
| 键盘可达 | Tab/Shift+Tab 顺序合理，菜单栏下拉全部项目有 `keyboardShortcut` |
| 屏幕阅读器 | SF Symbol 提供 `accessibilityLabel`，如 `Image(systemName: "gamecontroller.fill").accessibilityLabel("已连接的手柄")` |
| 动效减弱 | 全局支持 `prefers-reduced-motion`，关闭非必要 transition |
| 触控目标 | 所有按钮最小 28×28pt（macOS HIG 比 iOS 宽松），菜单栏项目最小 22pt 高 |

---

## 12. Agent Prompt Guide（给前端 Agent）

**技术栈锁定**：Swift 5.9+ · SwiftUI 5+ · MenuBarExtra · IOKit · CoreBluetooth

**实现要点**：

1. **Design Token 落地**：用 Swift `enum DesignSystem` 暴露常量，颜色用 `Color("Brand600")` 走 Asset Catalog，间距用 `CGFloat` 常量从 CSS token 编译时生成。**禁止任何 `.foregroundColor(Color(red:..., green:..., blue:...))` 直写**

2. **菜单栏图标**：必须使用 SF Symbol `gamecontroller.fill`（macOS 14+），旧系统回退 `gamecontroller`。在 SwiftUI 中用 `Image(systemName:)` + `.imageScale(.small)`

3. **手柄 SVG**：用 `Path` + `Shape` 程序化绘制 PS4 DualShock 4 外形（程序化 SVG 比引位图更利于深色模式自适应和动态高亮）。按键位置硬编码为 enum `case l1, r1, triangle, circle, ...`

4. **动作选择器 Sheet**：用 `.sheet(isPresented:)` + `.presentationDetents([.medium, .large])`（macOS 13+ 提供），搜索框用 `.searchable(text:)` modifier

5. **Onboarding 多步**：用 `TabView(selection:)` + `.tabViewStyle(.page)`，或自建 `Step` enum + progress bar

6. **键盘事件模拟**：用 `CGEvent` 注入鼠标/键盘事件，需 Accessibility 权限。封装为 `InputSimulator` actor

7. **Profile 切换**：用 `@AppStorage("currentProfile")` 持久化，订阅 `objectWillChange` 广播到 UI

**关键风险与提示**：

- [!]️ macOS 14 之前 MenuBarExtra 不存在，需用 `NSStatusItem` + 自定义 `NSMenu`，不能直接用 SwiftUI MenuBarExtra
- [!]️ CoreBluetooth 在 macOS 上需要"蓝牙权限"（`NSBluetoothAlwaysUsageDescription`），不是自动获取
- [!]️ Accessibility 权限检测用 `AXIsProcessTrustedWithOptions`，不要用 `kAXTrustedCheckOptionPrompt`（会反复弹窗骚扰用户）
- [!]️ CGEvent 注入在 Apple Silicon 上需要特殊权限码（entitlements）

---

## 13. 设计自查清单（对照 P0 红线）

| # | 自查项 | 通过 |
|---|--------|------|
| 1 | 无 emoji 作为功能图标（正则扫描零 emoji，所有图标 SF Symbols） | [V] |
| 2 | 无紫色→粉色渐变（`#7C3AED`/`#A855F7`/`#EC4899` 之间任意组合） | [V] |
| 3 | 无 AI 模板味（无 `Welcome to`/`Lorem ipsum`/千篇一律 Hero） | [V] |
| 4 | 无默认靛蓝 `#6366F1` | [V] |
| 5 | 无侧条纹彩色边框（`border-left: 3px solid var(--accent)`） | [V] |
| 6 | 无渐变文字（`background-clip: text`） | [V] |
| 7 | 无默认毛玻璃（菜单栏下拉除外，使用 `material(.popover)`） | [V] |
| 8 | 所有颜色通过 Design Token 引用，零硬编码 hex（除 `#fff` `#000`） | [V] |
| 9 | 间距全是 4px 整数倍（`--space-1` 到 `--space-16`） | [V] |
| 10 | 字体指定 SF Pro + PingFang SC + 等宽 fallback | [V] |
| 11 | 字号层级 ≤ 7 级 | [V] |
| 12 | 标题/正文/等宽三种字体有明确层级 | [V] |
| 13 | 主色（Steel Blue 600）每屏 ≤ 2 处强调使用 | [V] |
| 14 | 菜单栏图标在浅色/深色模式都识别度足够 | [V] |
| 15 | 按钮含 5 态（Default/Hover/Active/Focus/Disabled），输入框含 5 态 | [V] |
| 16 | 手柄按键含 6 态（Default/Hover/Selected/Pressed/Disabled/Unmapped） | [V] |
| 17 | 表单有验证错误态，列表有空状态 | [V] |
| 18 | 焦点环 3px `--brand-600` 30% 半透明，对比度 ≥ 3:1 | [V] |
| 19 | 动效全部 ≤ 360ms（按钮 80ms / 状态 150ms / Sheet 360ms） | [V] |
| 20 | 支持 `prefers-reduced-motion`（关闭非必要 transition） | [V] |
| 21 | 对比度达标：主文本 ≥ 7:1，副文本 ≥ 4.5:1（实际 16.8:1 / 5.7:1） | [V] |
| 22 | 响应式：主窗口 600-900pt 范围可调，< 700pt 自动单栏布局 | [V] |
| 23 | 触摸目标 ≥ 28×28pt（macOS HIG） | [V] |
| 24 | 图标尺寸统一：14/16/20/24px 四级 | [V] |
| 25 | 图标库单一：仅 SF Symbols，不混用 emoji / 自绘 PNG | [V] |
| 26 | 选中菜单栏图标立即生效（≤ 150ms 反馈脉冲） | [V] |
| 27 | 改键流程 ≤ 4 步（点图标→打开编辑器→选键→选动作） | [V] |
| 28 | 文案具体：`重新连接蓝牙` 非 `重连`；`更换动作` 非 `修改` | [V] |
| 29 | 不引用 `preferences` 命名，全部 `settings` | [V] |
| 30 | 退出菜单永远在底部，独立一栏，红字 | [V] |

---

## 附录 A：关键技术决策记录

| 决策 | 选择 | 备选 | 理由 |
|------|------|------|------|
| 主色 | Steel Blue 600 `#1E5BAF` | 默认靛蓝 / 墨绿 / 钢灰 | 避紫粉 + 呼 PS4 品牌 + macOS 菜单栏识别度 |
| 寄存器 | Product Register（克制策略）| Brand Register（落地页）| 工具型 App，需要"熟悉的可信感"而非"独特性" |
| 设计风格 | Swiss Minimalism（瑞士极简）| Glassmorphism / Vibrant | 工具属性 + macOS HIG 一致 |
| 图标库 | SF Symbols 5 | Lucide / 自定义 SVG | 0 成本 + 与系统字体对齐 + 矢量 + 暗色适配 |
| 编辑器范式 | 点击手柄键 + 弹出动作 Sheet（学 Steam）| 拖拽（学 Stream Deck）| macOS HIG 倾向直接操作 + 学习成本最低 |
| Profile 切换反馈 | 150ms 图标颜色脉冲 | Toast 提示 | 不打断当前使用，菜单栏上下文内自洽 |
| Onboarding | 4 步 Sheet | 全屏引导 | macOS 标准，非移动 App 不需要全屏 |
| 浅/深色 | 双模式均默认启用 | 仅深色 | macOS 用户强偏好（Sonoma 70%+ 用深色），双模式必做 |
| 关闭主窗口 | 隐藏而非退出 | 退出 | 菜单栏 App 标准行为（Slack/Bartender 都这样） |
| 菜单栏图标 | `gamecontroller.fill` | 自定义 PNG | 矢量 + 系统字体对齐 + 状态切换易 |

---

**版本**：v1.0
**最后更新**：2026-10-18
**设计者**：颜好看 · MVP 开发专家团
**下游交接**：架构师 + 前端 Agent（按 §12 Agent Prompt Guide 实现）
