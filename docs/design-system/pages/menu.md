# Page: 主菜单（MenuBarExtra 下拉）

> 此文件覆盖 MASTER.md，仅写差异字段。

## 覆盖字段

### 路由
- 触发：单击菜单栏 `gamecontroller.fill` 图标
- 容器：macOS MenuBarExtra / NSMenu（macOS 13- 用 NSStatusItem，macOS 14+ 用 MenuBarExtra）

### 尺寸
- 宽 280pt，高自适应（最大 480pt）
- 圆角：菜单栏系统默认（`material(.popover)`）

### 布局
单列，纵向 4 段：
1. **状态头**：图标 + 连接状态 + 电池
2. **启用 Toggle**
3. **Profile 切换 Submenu**（含编辑入口）
4. **动作组**：重新连接蓝牙 / 打开编辑器 / 设置 / 帮助
5. **退出**（独立栏，红字）

### 组件清单
- `MenuBarStatusHeader` — 图标 + 状态 + 电池
- `MenuToggleRow` — 图标 + 文字 + Switch
- `ProfileSubmenu` — 主项 + Submenu（4 项 + 分隔线 + "编辑 Profile…"）
- `MenuActionRow` — 图标 + 文字 + 快捷键（右对齐 tertiary）
- `MenuDivider` — 系统标准 1px 分隔线
- `MenuQuitItem` — 红色字，最后一项

### 视觉差异（vs MASTER）
- 背景：透明 + 系统 `material(.popover)`（macOS 自动深浅适配）
- 文字：14pt 400 正文；快捷键 12pt tertiary 右对齐
- 危险色仅用于退出项：`--color-danger`

### 交互细节
- 切换启用 → 菜单栏图标颜色脉冲 150ms（`--brand-600` ↔ `--neutral-500`）
- 切换 Profile → 立即生效，无 Sheet，无 Toast
- 退出 → 应用终止，菜单栏图标消失

### ASCII 草图
```
┌──────────────────────────────────────┐
│ ┌──┐  DS4Mate            [Gear] 设置│
│ │V │  DualShock 4 已连接    ⌘E 编辑 │
│ └──┘  [■■■■■■■■] 100%                │
├──────────────────────────────────────┤
│ [>]  启用映射            [●━━○] ON  │
├──────────────────────────────────────┤
│ 当前 Profile                       ▸ │
│   ● 默认                              │
│   ○ 媒体控制                          │
│   ○ 演示遥控                          │
│   ────                                │
│   ○ 编辑 Profile…                     │
├──────────────────────────────────────┤
│   [Bt] 重新连接蓝牙        ⌘R        │
│   [Edit] 打开编辑器        ⌘E        │
│   [Gear] 设置…             ⌘,        │
│   [?] 使用帮助                        │
├──────────────────────────────────────┤
│ 退出 DS4Mate              ⌘Q        │
└──────────────────────────────────────┘
```

### 5 态
| 组件 | Default | Hover | Selected | Disabled | Loading |
|------|---------|-------|----------|----------|---------|
| 菜单项 | 透明 + 系统色 | bg `--bg-hover` | bg `--bg-selected`，text `--fg-brand` | opacity 0.4 | 不适用 |
| Toggle | off：灰空圆 | — | on：蓝填充圆 | — | — |
