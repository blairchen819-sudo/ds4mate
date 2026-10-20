# DS4Mate 设计系统 MASTER

> 全局设计源文件。**单源真相（Single Source of Truth）**。
> 所有页面设计必须先读此文件，再检查 `pages/<page>.md` 是否存在覆盖。

---

## 1. 设计寄存器

**类型**：Product Register（产品型）
**对标**：Apple System Settings、Linear、BetterTouchTool、Stream Deck
**设计哲学**：专业 · 物理精确 · 静默常驻

---

## 2. 主色决策

**主色**：`Steel Blue 600 = #1E5BAF`（深蓝偏冷）
**理由**：避开紫粉 + 呼应 PS4 蓝 + macOS 菜单栏识别度高 + 11.2:1 对比度

**反词**：紫粉渐变、默认靛蓝 `#6366F1`、侧条纹彩色边框

---

## 3. Design Tokens（完整定义）

### A1 - Identity Token

```css
:root {
  /* Brand: Steel Blue 600 */
  --brand-50:  #EEF4FC;
  --brand-100: #D6E4F7;
  --brand-200: #A9C5EB;
  --brand-300: #7BA4DE;
  --brand-400: #4A82D0;
  --brand-500: #2A6BC2;
  --brand-600: #1E5BAF;  /* * 主色 */
  --brand-700: #174887;
  --brand-800: #103562;
  --brand-900: #0A2240;

  /* Neutral: Warm Slate */
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
```

### A2 - Structure Token

```css
:root {
  /* Spacing (4px 基准) */
  --space-0: 0; --space-1: 4px; --space-2: 8px; --space-3: 12px;
  --space-4: 16px; --space-5: 20px; --space-6: 24px; --space-8: 32px;
  --space-10: 40px; --space-12: 48px; --space-16: 64px;

  /* Radius */
  --radius-xs: 4px; --radius-sm: 6px; --radius-md: 8px;
  --radius-lg: 12px; --radius-xl: 16px; --radius-pill: 9999px;

  /* Shadow */
  --shadow-none: none;
  --shadow-xs: 0 1px 2px rgba(15, 23, 42, 0.05);
  --shadow-sm: 0 1px 3px rgba(15, 23, 42, 0.08), 0 1px 2px rgba(15, 23, 42, 0.04);
  --shadow-md: 0 4px 12px rgba(15, 23, 42, 0.08), 0 2px 4px rgba(15, 23, 42, 0.04);
  --shadow-lg: 0 12px 32px rgba(15, 23, 42, 0.10), 0 4px 8px rgba(15, 23, 42, 0.06);

  /* Motion */
  --motion-instant: 80ms;
  --motion-fast: 150ms;
  --motion-base: 220ms;
  --motion-slow: 360ms;
  --ease-standard: cubic-bezier(0.2, 0, 0, 1);
  --ease-emphasized: cubic-bezier(0.32, 0.72, 0, 1);
}
```

### A2 - Semantic Token

```css
:root {
  --color-success: #15803D; --color-success-bg: #DCFCE7; --color-success-fg: #14532D;
  --color-warning: #B45309; --color-warning-bg: #FEF3C7; --color-warning-fg: #78350F;
  --color-danger:  #B91C1C; --color-danger-bg: #FEE2E2; --color-danger-fg: #7F1D1D;
  --color-info:    #1E5BAF; --color-info-bg: #EEF4FC; --color-info-fg: #103562;
}
```

### B - Slot Token

```css
:root {
  /* Surface */
  --bg-app:      #F8FAFC;
  --bg-window:   #FFFFFF;
  --bg-sunken:   #F1F5F9;
  --bg-overlay:  rgba(15, 23, 42, 0.45);
  --bg-hover:    rgba(30, 91, 175, 0.08);
  --bg-selected: #EEF4FC;
  --bg-key-down: #D6E4F7;

  /* Foreground */
  --fg-primary:   #0F172A;
  --fg-secondary: #475569;
  --fg-tertiary:  #64748B;
  --fg-disabled:  #94A3B8;
  --fg-on-brand:  #FFFFFF;
  --fg-brand:     #1E5BAF;

  /* Border */
  --border-default: #E2E8F0;
  --border-strong:  #CBD5E1;
  --border-focus:   #2A6BC2;
  --border-subtle:  #F1F5F9;

  /* Focus ring */
  --focus-ring: 0 0 0 3px rgba(30, 91, 175, 0.30);
}

:root[data-theme="dark"] {
  --bg-app:      #0F172A;
  --bg-window:   #1E293B;
  --bg-sunken:   #0B1220;
  --bg-overlay:  rgba(0, 0, 0, 0.55);
  --bg-hover:    rgba(255, 255, 255, 0.06);
  --bg-selected: rgba(30, 91, 175, 0.20);
  --bg-key-down: rgba(30, 91, 175, 0.35);

  --fg-primary:   #F1F5F9;
  --fg-secondary: #CBD5E1;
  --fg-tertiary:  #94A3B8;
  --fg-disabled:  #475569;

  --border-default: #334155;
  --border-strong:  #475569;
  --border-subtle:  #1E293B;

  --focus-ring: 0 0 0 3px rgba(122, 164, 222, 0.45);
}
```

### Typography

```css
--font-display: 'SF Pro Display', 'SF Pro', 'PingFang SC', system-ui, sans-serif;
--font-body:    'SF Pro Text',    'SF Pro', 'PingFang SC', system-ui, sans-serif;
--font-mono:    'SF Mono',        'Menlo', monospace;

--text-xs:  11px;  /* 标签、徽章 */
--text-sm:  12px;  /* 辅助说明 */
--text-base: 13px; /* 主窗口正文 */
--text-md:  14px;  /* 列表项 */
--text-lg:  16px;  /* 节区标题、按钮 */
--text-xl:  18px;  /* 主窗口一级标题 */
--text-2xl: 22px;  /* 弹窗标题 */
--text-3xl: 28px;  /* Onboarding 标题 */
```

### Icon System

- **库**：SF Symbols 5（macOS 14 Sonoma+ 含 5000+ 图标，含游戏控制器分类）
- **尺寸**：14 / 16 / 20 / 24 px（菜单栏 / 行内 / 按钮内 / 独立）
- **渲染**：`SymbolRenderingMode.hierarchical` 优先，multicolor 仅限媒体图标

---

## 4. 全局组件规范

### Button（5 态）

| 状态 | 视觉 |
|------|------|
| Default | bg `--brand-600`，text `--fg-on-brand`，radius `--radius-sm`，padding 10×16 |
| Hover | bg `--brand-700` |
| Active | bg `--brand-800`，scale 0.98 |
| Focus | `var(--focus-ring)` 3px |
| Disabled | opacity 0.4 |
| Loading | Spinner + 文案 |

### Input（5 态）

| 状态 | 视觉 |
|------|------|
| Default | bg `--bg-sunken`，border `--border-default` |
| Focus | border `--border-focus`，加 `var(--focus-ring)` |
| Error | border `--color-danger` |
| Disabled | bg `--neutral-100`，text `--fg-disabled` |
| Read-only | 无 border，下划线样式 |

### 手柄按键（6 态，编辑器专用）

| 状态 | 视觉 |
|------|------|
| Default | bg `--bg-window`，border 1px `--border-default` |
| Hover | border `--brand-400` |
| Selected | bg `--bg-selected`，border 2px `--brand-600` |
| Pressed (回显) | bg `--bg-key-down`（150ms 闪） |
| Disabled | opacity 0.3 |
| Unmapped | 加 SF Symbol `questionmark` 角标 |

---

## 5. SF Symbols 全局选型

### 菜单栏图标（按状态）
- `gamecontroller.fill`（已连+启用）· `gamecontroller`（已连+禁用）· `gamecontroller.slash`（未连）· `exclamationmark.triangle.fill`（错误）

### 工具栏图标
- `plus` · `arrow.uturn.backward` · `arrow.uturn.forward` · `tray.and.arrow.down` · `trash` · `magnifyingglass`

### 类别图标
- 鼠标 `computermouse` · 键盘 `keyboard` · 系统 `gearshape.2` · 媒体 `speaker.wave.2` · 自定义 `wand.and.stars`

### 状态图标
- `checkmark.circle.fill`（成功）· `xmark.circle.fill`（失败）· `exclamationmark.triangle.fill`（警告）· `info.circle.fill`（信息）· `lock.shield`（权限）

完整动作图标库（28 个）见 `pages/editor.md`。

---

## 6. 全局原则（Do's and Don'ts）

### [V] Do
- 所有颜色用 Token，零硬编码 hex
- 所有图标用 SF Symbols，零 emoji
- 主色每屏 ≤ 2 处
- 5 态覆盖按钮、输入框、按键
- 双模式（浅/深色）
- 真实产品内容（手柄编辑器），不堆抽象图形

### [X] Don't
- 紫粉渐变
- emoji 作功能图标
- 侧条纹彩色边框
- 默认靛蓝 `#6366F1`
- 渐变文字
- 默认毛玻璃（菜单栏下拉除外）
- "Welcome to" / "Lorem ipsum"
- AI 编号 section（01 / 02 / 03）

---

## 7. 全局反模式（错误模板）

```swift
// [X] 圆角卡片 + 彩色左边框（AI 标志）
.overlay(alignment: .leading) {
    Rectangle().fill(Color.blue).frame(width: 3)
}

// [V] DS4Mate 风格——统一边框，hover 时变色
.background(.window)  // var(--bg-window)
.overlay(RoundedRectangle(cornerRadius: 8).stroke(.border))
.onHover { hovering in /* border 变 brand */ }
```

---

## 8. Agent Prompt 摘要

- 用 Swift `enum DesignSystem` 暴露常量，颜色走 Asset Catalog `Color("Brand600")`
- 菜单栏图标必须用 SF Symbol（macOS 14+），旧系统回退 `gamecontroller`
- 手柄 SVG 用 `Path` + `Shape` 程序化绘制
- 动作选择器用 `.sheet(isPresented:)` + `.presentationDetents([.medium, .large])`
- Onboarding 用 `TabView` + `.tabViewStyle(.page)`
- 输入模拟用 `CGEvent`，封装 `InputSimulator` actor
- Profile 切换用 `@AppStorage("currentProfile")` + 广播

完整实现要点见 `/docs/DESIGN.md` §12。
