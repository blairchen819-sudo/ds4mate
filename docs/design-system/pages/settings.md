# Page: 设置窗口

> 此文件覆盖 MASTER.md，仅写差异字段。

## 路由
- 触发：菜单栏 → 设置（⌘,）
- 容器：标准 macOS `Settings` 协议（macOS 13+ 提供）

## 尺寸
- 640 × 480pt（macOS Settings 标准）
- 单例窗口

## 布局
**左右双栏**（macOS Settings 风格）：
- 左侧 Sidebar：4 个分类
- 右侧 Detail：表单内容

## 组件清单
- `SettingsSidebar` — `List` + `.sidebar` style，4 项
- `SettingsDetail` — `Form` + sections

### 4 个分类

#### 1. 输入（Input）
- 鼠标灵敏度：Slider（0.1 - 3.0，步长 0.1，默认 1.0）
- 摇杆死区：Slider（0% - 30%，步长 1%，默认 15%）
- [ ] 启用按键回显（屏幕显示按下键）
- [ ] 按住 SHARE 键暂停映射
- 快捷键：
  - 切换启用：⌃⌥ Space（可改键）
  - 切换 Profile：⌃⌥ P（可改键）

#### 2. 显示（Display）
- 菜单栏图标样式：3 选 1 Radio
  - 始终显示彩色（默认）
  - 仅显示灰度（节能）
  - 仅在启用时显示
- [ ] 显示电池百分比
- [ ] 显示映射已启用徽章

#### 3. 权限（Permissions）
- Accessibility（辅助功能）：● 已授权 / ○ 未授权 + [打开系统设置]
- Bluetooth：● 已授权 / ○ 未授权 + [打开系统设置]
- Input Monitoring：● 已授权 / ○ 未授权 + [打开系统设置]
- 顶部文案：DS4Mate 需要以下权限才能模拟键鼠事件

#### 4. 关于（About）
- DS4Mate Logo + 版本号（v1.0.0）
- 检查更新（按钮）
- 致谢（展开 DisclosureGroup）
- GitHub 仓库链接（按钮 → 浏览器）
- 许可协议（展开 DisclosureGroup）

## 视觉差异（vs MASTER）
- Sidebar：标准 macOS `List` + `.sidebar` style
- 颜色状态指示：● 实心绿 = 已授权 / ○ 空心黄 = 未授权
- 全部表单组件走 `Form` + `Section`（系统标准）
- 快捷键录制用 `KeyboardShortcut` modifier（macOS 13+）

## 交互细节
- 修改滑块 → 实时预览（手柄移动立即响应）
- 录制快捷键：点击"录制" → 弹出小弹窗 → 按下快捷键 → 自动填充
- 权限状态每 3 秒轮询检测（从 AXIsProcessTrusted 等 API）
- 检测到权限变更 → 自动重新启用映射

## ASCII 草图
```
┌──────────────┬─────────────────────────────────────┐
│              │  [Gear] 输入                         │
│  输入        │  ───────────                         │
│  显示        │  鼠标灵敏度    [━━━━━○────]  中       │
│  权限        │  摇杆死区      [━━━○──────]  15%     │
│  关于        │                                     │
│              │  [ ] 启用按键回显（屏幕显示按下键）     │
│              │  [ ] 按住手柄 SHARE 键暂停映射         │
│              │                                     │
│              │  快捷键                              │
│              │  ───────────                         │
│              │  切换启用：  ⌃⌥ Space      [录制]    │
│              │  切换 Profile：⌃⌥ P         [录制]    │
└──────────────┴─────────────────────────────────────┘
```

## 5 态
| 组件 | Default | Hover | Selected | Disabled | Loading |
|------|---------|-------|----------|----------|---------|
| Sidebar 项 | 系统样式 | 系统 highlight | 系统 accent | — | — |
| Slider | 系统样式 | — | 拇指按下变 `--brand-700` | opacity 0.4 | — |
| 权限状态点 | ● 绿 / ○ 黄 | — | — | — | 检测中：spinner |
| 录制快捷键按钮 | 文字"录制" | 文字"按下快捷键…" | 录制完成后显示按键 | — | — |
