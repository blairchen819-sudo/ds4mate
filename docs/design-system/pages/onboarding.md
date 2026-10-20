# Page: 首次启动引导（Onboarding）

> 此文件覆盖 MASTER.md，仅写差异字段。

## 路由
- 触发：V1 首次启动（检测 `~/Library/Application Support/DS4Mate/onboarded.flag` 不存在）
- 容器：macOS Sheet（非全屏，4 步）

## 尺寸
- 540 × 440pt
- 圆角：16pt

## 布局
**多步 Sheet**：
- 顶部：进度条（4 段）+ 步骤计数 `N/4`
- 中部：插画 + 标题 + 描述 + 行动项
- 底部：上一步 / 下一步 / 主要 CTA

## 4 个步骤

### Step 1/4：欢迎
- 插画：手柄 SVG 简化版（带 SF Symbol `gamecontroller.fill`）
- 标题：「把 PS4 手柄变成 Mac 鼠标」
- 描述：「DS4Mate 通过蓝牙连接你的 DualShock 4，把按键和摇杆映射成 macOS 的鼠标和键盘事件。」
- CTA：「开始设置 →」

### Step 2/4：Accessibility 权限
- 插画：`lock.shield` SF Symbol + 盾牌插画
- 标题：「授权 macOS 辅助功能」
- 描述：
  - macOS 要求应用获得"辅助功能"权限才能模拟键盘和鼠标事件
  - 1. 打开系统设置
  - 2. 找到 DS4Mate 并打开开关
  - 3. 返回此窗口继续
- CTA：[打开系统设置]（深链 x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility） + [已手动开启]
- 灰化「下一步」直到 `AXIsProcessTrusted()` 返回 true

### Step 3/4：蓝牙配对
- 插画：`personalhotspot` + 旋转动画 `.symbolEffect(.rotate)` 表示扫描中
- 标题：「连接你的 DualShock 4」
- 描述：
  - 长按手柄 SHARE + PS 键 3 秒直到顶部灯条快速闪烁
  - 点击下方按钮开始扫描
- 检测到的设备列表（最多 3 项）：
  - ◌ Wireless Controller            [配对]
  - ◌ Wireless Controller (2)        [配对]
- CTA：[重新扫描] + [下一步 →]
- 灰化「下一步」直到至少一个设备配对成功

### Step 4/4：试玩
- 插画：`target` SF Symbol + 计数器
- 标题：「试一下默认映射」
- 描述：按下手柄按键测试映射是否生效
- 实时检测列表：
  - [OK] 左摇杆推动鼠标（已检测 3 次）
  - [OK] △ 已映射 Y 键（已检测 1 次）
  - [ ] ○ 已映射 ← 键（未检测）
- 当 3 个核心键均检测 → 显示 "[OK] 全部完成！"
- CTA：[打开编辑器 →]

## 视觉差异（vs MASTER）
- Sheet 大圆角：16pt
- 进度条：4 段，每段 25% 宽，已完成 `--brand-600`，未完成 `--border-default`
- 步骤计数：`N/4` 文字 12px tertiary 右对齐
- 插画区：高 200pt，居中
- 标题：22px 590 字重 -0.01em 字距
- 描述：13px 400，行高 1.5
- 步骤列表：每个项高 36pt，SF Symbol + 文字

## 交互细节
- 任何一步允许"跳过"（右上角小"跳过引导"链接）
- 「上一步」仅在非 Step 1 时显示
- 「下一步」在条件未满足时灰化
- 完成最后一步 → 写入 onboarded.flag → Sheet 自动关闭
- 任何步骤都可"关闭窗口" → 不写 flag，下次启动重进 Onboarding

## ASCII 草图（Step 2）

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
│  1. 打开系统设置                             │
│  2. 找到 DS4Mate 并打开开关                  │
│  3. 返回此窗口继续                           │
│                                              │
│       [打开系统设置]   [已手动开启]           │
└──────────────────────────────────────────────┘
```

## 5 态
| 组件 | Default | Hover | Selected | Disabled | Loading |
|------|---------|-------|----------|----------|---------|
| CTA 按钮 | 见 MASTER Button | — | — | opacity 0.4 + cursor not-allowed | spinner + 文案 |
| 检测项（已完成） | text `--fg-primary`，[OK] `--color-success` | — | — | — | 检测中 spinner |
| 检测项（未检测） | text `--fg-tertiary`，[ ] 中性 | — | — | — | — |
| 跳过链接 | text 12px `--fg-tertiary` | text `--fg-brand` | — | — | — |
