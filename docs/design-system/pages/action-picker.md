# Page: 动作选择器 Sheet

> 此文件覆盖 MASTER.md，仅写差异字段。

## 覆盖字段

### 路由
- 触发：编辑器右栏「更换动作」按钮
- 容器：macOS `.sheet(isPresented:)`，`.presentationDetents([.medium, .large])`

### 尺寸
- 默认 `.medium`（约 480pt 高）
- 可拉至 `.large`（约 720pt 高）
- 宽 560pt

### 布局
**三段**（垂直）：
1. 顶部：标题栏 + 搜索框（`.searchable` modifier）
2. 中部：分类标签（Segmented）+ 动作卡片 4 列网格
3. 底部：最近使用（最多 5 个）

### 组件清单
- `SheetHeader` — 标题 + 关闭按钮
- `SearchField` — `.searchable` 自动 focus + 模糊匹配
- `CategoryTabs` — Segmented：鼠标 / 键盘 / 系统 / 媒体（4 个）
- `ActionGrid` — 4 列 LazyVGrid，120×80pt 卡片
- `ActionCard` — SF Symbol + 动作名 + 别名
- `RecentActions` — LRU 横向 Row，最多 5 个

### 视觉差异（vs MASTER）
- Sheet 圆角：16pt（`--radius-xl`）
- Sheet 阴影：`--shadow-lg`
- 搜索框背景：`--bg-sunken`，圆角 `--radius-sm`
- 分类标签：选中态 bg `--bg-selected`，text `--fg-brand`
- 动作卡片：120×80pt，padding 16pt 内部，gap 8pt symbol↔text

### 交互细节
- 打开 Sheet → 搜索框自动 focus
- 输入即搜：200ms debounce，模糊匹配动作名 + 别名 + 键码
- 点击分类标签 → 切换动作集合，搜索词保留
- 点击动作卡片 → 立即应用 + Sheet 关闭（带 0.3s 视觉确认再关）
- ESC 键 → 关闭 Sheet 不应用
- ⌘1-4 → 切换分类（标签上标快捷键数字）
- 最近使用：LRU 缓存，跨 Profile 不共享，持久化到 UserDefaults

### ASCII 草图
```
┌──────────────────────────────────────────────────┐
│  选择动作                                    [X] │
│  [Q] [搜索：鼠标、键盘、媒体…         ]       │
├──────────────────────────────────────────────────┤
│  [鼠标 4]  [键盘 8]  [系统 3]  [媒体 5]          │
│                                                  │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
│  │  Mo  │  │  Mo  │  │  Mo  │  │  Mo  │         │
│  │ 左键  │  │ 右键  │  │ 中键  │  │ 滚轮↑│         │
│  │ 单击  │  │ 单击  │  │ 单击  │  │ 上滚 │         │
│  └──────┘  └──────┘  └──────┘  └──────┘         │
│                                                  │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐         │
│  │  Mo  │  │  Mo  │  │  Mo  │  │  Mo  │         │
│  │ 滚轮↓ │  │ 滚轮← │  │ 滚轮→ │  │ 双击 │         │
│  └──────┘  └──────┘  └──────┘  └──────┘         │
│                                                  │
│  ── 最近使用 ─────────────────────               │
│  [Mo·左键] [⌘C] [⏯ Play/Pause] [Esc] [Spc]  │
└──────────────────────────────────────────────────┘
```

### 5 态
| 组件 | Default | Hover | Selected | Disabled | Loading |
|------|---------|-------|----------|----------|---------|
| 动作卡片 | bg `--bg-window`，border 1px | border `--brand-400`，bg `--bg-hover` | border 2px `--brand-600`，左上 [OK] | opacity 0.3 | 不适用 |
| 分类标签 | bg 透明，text `--fg-secondary` | bg `--bg-hover` | bg `--bg-selected`，text `--fg-brand` | — | — |
| 搜索框 | bg `--bg-sunken`，border 透明 | — | border `--border-focus` + `--focus-ring` | opacity 0.4 | "搜索中…" spinner |

### 完整状态
- **Empty（首次打开）**：显示分类 + 4 个默认动作 + 提示
- **Searching**：搜索框聚焦，分类淡出保留顶部
- **Populated**：4 列网格 + 最近使用
- **No results**：居中插画（SF Symbol `questionmark.diamond`）+ 文案「未找到 'xxx'，试试其他关键词」+ 「清除搜索」按钮
- **Selected**：卡片勾选 + 0.3s 反馈 + 自动关闭
- **Network/Loading**：动作库加载时全 Sheet 显示 Spinner（首次冷启动）
