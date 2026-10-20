# Page: 主窗口 — 可视化键位编辑器（核心）

> 此文件覆盖 MASTER.md，仅写差异字段。

## 覆盖字段

### 路由
- 菜单栏 → 打开编辑器（⌘E）
- 单例 NSWindow，关闭 = 隐藏不退出

### 尺寸
- 默认 720 × 520pt
- 最小 600 × 420pt
- 最大 900 × 700pt
- 圆角：12pt（macOS 系统圆角即可）

### 布局
**双栏 HSplitView**（自适应）：
- 左栏：手柄可视化区（≥380pt）
- 右栏：动作配置区（≥340pt）
- 底部：工具栏（固定高 44pt）

### 左栏组件（手柄可视化）
- `ControllerView`：PS4 DualShock 4 程序化 SVG（`Path` + `Shape`）
- `ControllerButton`：14 个按键可点击组件（每个独立 entity）
- `MappingStatusBar`：「已映射 X / 14 键」

**按键清单**（按 PS4 实际位置）：
| Key 名 | 位置 | SF Symbol |
|--------|------|-----------|
| `l1` / `r1` | 顶部肩键 | `l1.rectangle.roundedbottom` / `r1.rectangle.roundedbottom` |
| `l2` / `r2` | 顶部扳机 | `l2.rectangle.roundedtop` / `r2.rectangle.roundedtop` |
| `triangle` | 右侧动作键 顶 | `triangle.fill` |
| `circle` | 右 | `circle.fill` |
| `cross` | 底 | `xmark` |
| `square` | 左 | `square.fill` |
| `up` / `down` / `left` / `right` | 左侧 D-Pad | `arrow.up/down/left/right` |
| `l3` / `r3` | 双摇杆按下 | `dot.circle` |
| `share` | 左中 | `square.and.arrow.up` |
| `options` | 右中 | `square.and.arrow.down` |
| `ps` | 中间 | `p.circle` |
| `touchpad` | 顶部中央触摸板 | `rectangle.dashed` |

**手柄按键 6 态**：见 MASTER.md §4
**实时回显**：当 HID 报告检测到按键 release，触发 150ms `--bg-key-down` 闪。

### 右栏组件（动作配置）
- `SelectedKeyHeader`：键名 + SF Symbol + 当前激活触发方式
- `ActionSlotList`：1-4 个动作槽位（单击 / 双击 / 长按 / 按住）
- `ActionSlot`：当前动作 + 「更换」按钮
- `TriggerPicker`：触发方式下拉（单击 / 双击 / 长按）
- `ActionButtonRow`：「更换动作」+「清除」

### 底部工具栏
- `+ 新增键映射`（Power User 进入"自定义虚拟键"模式）
- `↶ 撤销` / `↷ 重做`（栈深度 20）
- `Save 保存`（脏数据时高亮 `--brand-600`；已保存灰化）
- `导出 JSON`（Power Feature）

### 视觉差异（vs MASTER）
- 主窗口背景：`--bg-app`（`#F8FAFC` 浅 / `#0F172A` 深）
- 工具栏与内容间距：`--space-4`
- Section header 大写小标签（11px 510 字重，0.06em 字距）：`PROFILES` / `ACTIONS` / `TOOLS`

### ASCII 草图
```
┌────────────────────────────┬─────────────────────────────┐
│  [Profile: 默认 ▾]   [+]  │  选中键：△ Triangle         │
│                            │  ───────────────             │
│                            │  当前动作：                  │
│      ┌──────────────┐      │    [Mouse·中键单击]         │
│      │   [L2][R2]   │      │    [⇧ Shift]                │
│      │  [L1]    [R1] │      │                             │
│      │ [Share][Options]    │  ───────────────             │
│      │   [ ] PS ◯ △        │  触发方式：单击 ▾           │
│      │    [X]  [Touch]      │  连点间隔：— ms              │
│      │  [D-Pad]          │  长按延迟：500 ms             │
│      └──────────────┘      │                             │
│                            │  [ 更换动作 ]  [ 清除 ]      │
│  已映射：8 / 14 键         │                             │
├────────────────────────────┴─────────────────────────────┤
│ [+] 新增 [↶] [↷] [● 已修改] [Save 保存] [⇪ 导出]    │
└──────────────────────────────────────────────────────────┘
```

### 响应式
- < 700pt 宽：右栏自动收起为底部 Sheet（点击键 → Sheet 弹出动作选择器）
- ≥ 700pt：双栏（默认）
- 900pt+：手柄 SVG 放大至 1.2x

### 5 态
| 组件 | Default | Hover | Selected | Disabled | Loading |
|------|---------|-------|----------|----------|---------|
| 手柄按键 | bg `--bg-window`，border 1px `--border-default` | border `--brand-400` | bg `--bg-selected`，border 2px `--brand-600`，左侧 2px 条 | opacity 0.3 | 不适用 |
| 动作槽位 | bg `--bg-window`，border 1px | border `--brand-400` | border 2px `--brand-600` | opacity 0.4 | "应用动作中…" spinner |
| 工具栏按钮 | 见 MASTER Button | — | — | — | "保存中…" spinner |

### 完整动作图标库（28 个）

| 动作 | SF Symbol | 渲染 |
|------|-----------|------|
| **鼠标类（9）** | | |
| 左键单击 | `computermouse` | 单色 |
| 右键单击 | `computermouse.fill` + 角标 | 单色 |
| 中键单击 | `computermouse` + 中圆点 | 单色 |
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
| ⌘ C / V / X | `doc.on.doc` / `doc.on.clipboard` | 单色 |
| 组合键 | `command` + `option` + `control` 复合 | 多色 |
| **系统类（5）** | | |
| 截屏 | `camera.aperture` | 单色 |
| 调度中心 | `rectangle.3.group` | 单色 |
| 锁定屏幕 | `lock.fill` | 单色 |
| 退出应用 | `power` | 单色 |
| 显示桌面 | `menubar.dock.rectangle` | 单色 |
| **媒体类（4）** | | |
| 播放/暂停 | `playpause.fill` | 多色 |
| 上一曲 | `backward.fill` | 单色 |
| 下一曲 | `forward.fill` | 单色 |
| 静音 | `speaker.slash.fill` | 单色 |

> macOS 14+ SF Symbols 5 全支持；macOS 13 系统图标不全时用相邻符号 + 自定义 asset 兜底。
