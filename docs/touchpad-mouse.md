# 触摸板当鼠标（Touchpad → Pointer）

> 把 PS4 手柄触摸板变成能用的指针设备：手指滑动移动光标，轻按触摸板 = 鼠标左键。
> 走 IOKit 原始 HID，自行解析多子帧、插值、低通，240Hz 合成 CGEvent。

---

## 一、先纠正三个常见认知偏差

网上关于「macOS 上读 DS4 触摸板」的方案，有三个地方和实际不符。这三条决定了这条路能不能走通，值得先说清楚。

### 1. 蓝牙 DS4 默认拿不到触摸板，但不是 macOS 的限制

大量资料（包括项目早期自己的代码注释）都记着「macOS 只给 10 字节精简报告，比 Windows 少一半」。

实际原因是 **Sony 固件本身的默认档位**：DS4 通过蓝牙连接时本来只发精简 `0x01` 报告（10 字节，只有摇杆 / 按键 / 扳机），**必须先发一次 `GET_REPORT(feature, 0x02)`**（IMU 校准数据），固件才会切到完整 `0x11` 报告（78 字节，含触摸板 + IMU）。

这个 request 请求的是校准数据，但**真正的价值是它的副作用**——解锁完整报告。dsremap 的逆向文档里写得很明确：

> When the Dualshock is paired via Bluetooth, GET_REPORT 0x02 has the additional side effect of changing the input report type from the default 0x01 (pretty limited, with only buttons and triggers).

代码位置：`HIDControllerService.unlockFullReport(_:)`。

### 2. `kIOHIDOptionsTypeSeizeDevice` 这一步是多余且有风险的

「抢占设备让 GameController 别接管」这个思路来自 Windows 的 HidHide 习惯，但在 macOS 上不成立：

- 用户态 App 用 `SeizeDevice` 打开 HID 设备需要 **root 权限**，普通 App 直接返回 `kIOReturnNotPermitted`；
- 就算拿到了 root，seize 会**独占**设备，导致系统 GameController 和所有其他程序都读不到手柄——代价远大于收益；
- **关键是没必要**：`IOHIDDeviceOpen(kIOHIDOptionsTypeNone)` 就能正常收输入报告，DS4Mate 现有的按键读取一直就是这么工作的。多个进程同时读同一 HID 设备的输入报告是允许的。

所以本实现**不用 seize**。探针里保留 `--seize` 参数是为了方便对比验证，不是运行路径。

### 3. 「一包 4 个子帧」的真相（2026-11-06 真机抓包校准）

之前的描述（4 个多指槽位 × prev/cur 双子帧）**是错的**。实测这台 Mac mini + 蓝牙 DS4（`0x054C:0x09CC`，macOS 26）后得到的事实：

**报告层**
- `0x11` 报告 78 字节，**64 包/秒**（15.5ms 一包，比原来项目注释里写的 ~12Hz 高得多）
- `payload[34]` = 触摸事件数，实测在 **0 / 1 / 3 / 4** 之间变化

**事件层（每项 9 字节）**

| 偏移 | 内容 |
|---|---|
| `+0` | 时间戳（uint8，随采样递增） |
| `+1..+4` | 触点 A：`id / X低8 / 混合 / Y高8` |
| `+5..+8` | 触点 B：实测固件**恒为 `80 00 00 00`**（inactive） |

**触点 4 字节的位序**（这是最容易踩错的地方）

```
[0] id       bit7 = 1 表示该触点无效
[1] X 低 8 位
[2] 混合    高 4 位 = Y 低 4 位，低 4 位 = X 高 4 位
[3] Y 高 8 位

X = ((mesh & 0x0F) << 8) | xLow
Y = (yHigh << 4) | (mesh >> 4)
```

> 第一版实现把第 3 个字节当成 Y 低 8 位，结果 Y 溢出到 3.0（面板高度只有 943）。真机数据一跑就露馅了。

**所以真正的「多子帧」不是 prev/cur 双子帧，而是：一包里 3～4 个时间上先后排列的采样。**

3～4 个采样 × 64 包/秒 ≈ **200+ Hz 有效触摸采样率**。这才是平滑的物理基础，比「一包一个点」高一个数量级，也解释了为什么 DS4 触摸板在 PS4 上做鼠标那么跟手。

---

## 二、数据链路

```
DS4 触摸板（1920 × 943，12 bit 坐标）
  │
  │ 蓝牙 HID，64 包/秒（实测），每包 0~4 个触摸采样
  ▼
IOHIDManager  ── HIDControllerService
  │  • unlockFullReport(): GET_REPORT 0x02 → 切到 0x11 完整报告
  │  • handleReport(): 剥离 report ID，判定布局，统一解析按键
  ▼
DS4TouchParser  ── 纯逻辑
  │  • 自适应三种布局（精简 0x01 / USB 完整 0x01 / 蓝牙完整 0x11，含 0xC0 前缀）
  │  • 每包解出 0~4 个时间采样，按包间隔均匀铺开时间戳
  │  • 输出归一化 0…1 坐标序列 TouchpadFrame（有效采样率 200+ Hz）
  ▼
TouchpadPointerEngine  ── 纯算法，可单测
  │  • 采样入队（离群点抑制：6ms 内跳 35% 板宽视为坏包）
  │  • 240Hz tick，按 now − 10ms 在队列中线性插值
  │  • 速度自适应一阶低通（滞后大 → τ 小 → 更跟手）
  │  • 差分 → 像素位移；速度死区吞掉静止抖动；低速增益做精细定位
  ▼
TouchpadMouseService  ── 240Hz DispatchSourceTimer
  │  • 屏幕联合区域夹取（用 CGDisplayBounds，不是 NSScreen.frame）
  │  • 影子位置 + 触摸开始时校准，修掉「事件被某程序吞掉」的偏移
  ▼
CGEvent(.mouseMoved) → .cghidEventTap
  ▼
系统光标 / 前台 App
```

---

## 三、怎么验证（第一次上手必做）

**链路已于 2026-11-06 在本机实测跑通**（Mac mini / macOS 26 / 蓝牙 DS4 `0x09CC`）：

- `GET_REPORT(feature 0x02)` 返回 `0x00000000`，37 字节校准数据
- 随后报告从 `0x01 len=10` 直接切到 `0x11 len=78`，带 `0xC0 0x00` 前缀
- 触摸坐标持续输出，已用抓包样本锁进单测做回归

换设备 / 换系统版本后仍建议先跑一遍探针：

```bash
# 1. 编译探针
swiftc -O -o tools/hid-probe/ds4-probe \
    tools/hid-probe/main.swift Sources/DS4Mate/Services/DS4TouchParser.swift \
    -framework IOKit -framework CoreFoundation

# 2. 连上手柄（按住 Share + PS 进入配对模式，系统蓝牙里配对）

# 3. 采集 15 秒，期间先摇左摇杆，再在触摸板上慢慢划一条斜线
./tools/hid-probe/ds4-probe
```

### 判读输出

| 现象 | 含义 |
|------|------|
| 只有 `id=0x01 len=10` | 还在精简档位，触摸板无数据 |
| 出现 `id=0x11 len=78` | ✅ 成功（本机实测就是 78，不是文档里常写的 76） |
| `触摸区[32..47]` 里第 4 个字节（绝对偏移 35）随手指变化 | ✅ 事件计数在动，通常是 3 或 4 |
| 触摸坐标行 `slot0=(0.xxxx, 0.yyyy)` 且两者都 < 1.0 | ✅ 解析正确 |
| Y 值大于 1.0（如 3.0） | ✗ 触点字节序解反了，对照第 3 节位序表 |
| `GET_REPORT(feature 0x02) → 0xE00002E2` | 设备被独占，检查是否有其他程序占用 |
| `GET_REPORT … → 其他非 0` | 权限问题，去「隐私与安全性 → 输入监控」勾选终端 |

抓包辅助参数：`--hex N` 转储前 N 包完整字节；`--hex-touch N` 只在检测到手指时转储（推偏移用）。

如果发出 0x02 后**仍然没有 0x11**，说明 macOS 的 HID 层没把这个报告投递上来。那就需要走方案 C（见第七节），不能假装成功。

---

## 四、开关与手感调参

**设置 → 通用 → 触摸板**：

| 参数 | 默认 | 作用 |
|------|------|------|
| 触摸板当鼠标 | 关 | 总开关。开启后触摸板按下 = 鼠标左键，**原触摸板按键映射失效** |
| 灵敏度 | 2.6× | 手指滑满触摸板宽度 = 屏幕上移动 2.6 个屏宽 |
| 平滑度 | 0.45 | 0 = 原始跟手但有台阶感；1 = 极顺但明显滞后。0.3–0.6 是甜区 |
| 死区 | 4.0 pt/s | 低于该速度的抖动直接丢弃，防止静止时指针缓慢漂移 |

调参建议：

- **觉得飘 / 对不准** → 降灵敏度（1.8–2.2），升死区（6–10）
- **觉得拖沓 / 跟不上** → 降平滑度（0.2–0.3），降延迟（代码里 `PointerConfig.latency`，默认 10ms）
- **快速甩动时跳一下** → 这是蓝牙物理瓶颈，调参救不了，见第五节

设置页底部会显示诊断行：`报告 蓝牙完整 · 触摸包 1234`。如果显示「精简 0x01（未解锁）」，说明 0x02 没成功，触摸板不会有反应。

---

## 五、诚实的限制

按重要性排序：

1. **蓝牙链路抖动是物理瓶颈，代码解决不了**
   报告间隔不稳定、偶发丢包、低电量时固件主动降采样、2.4G WiFi 同频干扰——这些只能靠插值 + 低通掩盖，无法消除。表现是「慢速很顺，快速偶尔跳一下」。这和 Windows 蓝牙 DS4 是同一个瓶颈，不是 macOS 独有缺陷。想要极致稳定只能上有线。

2. **CGEvent 会被部分程序吞掉**
   `.cghidEventTap` 已经比 `.cgSessionEventTap` 更靠近硬件层，但某些独占渲染程序（AR/VR 渲染器、部分全屏游戏）仍可能不认合成事件。彻底解决要上 DriverKit 虚拟 HID，见第七节。

4. **多指手势未实现**
   目前只消费 slot 0（单指）。双指滚动、捏合缩放是后续工作。数据已经在 `TouchpadFrame.samples` 里了，缺的是手势识别层。

5. **第二触点位在本机固件上永远是空的**
   实测每一包的触点 B 恒为 `80 00 00 00`。所以「一包 3～4 个采样」是同一根手指的连续采样，不是多指。如果后续固件版本开始填 B，解析器会把它当第二个采样（半步长）处理，不会解码错，但需要在真机上重新看一遍时间间隔。

6. **USB 完整报告（64 字节）的触摸偏移未实测**
   本机只有蓝牙链路。USB 的 `eventCount=34 / events=35` 沿用社区文档，与蓝牙实测值一致，但没插过数据线验证。插线使用时如果坐标不对，看第一～三条。

5. **触摸板按下时指针不冻结**
   为了让「按住拖动选中文字」可用，按下瞬间不做冻结，靠速度死区吸收抖动。如果实测发现按下时指针会明显漂一下，把 `TouchpadMouseService.freezeWhileClicking` 改成 `true` 即可（代价是拖动失效）。

---

## 六、为什么是 240Hz 而不是「收到报告就移动」

蓝牙 DS4 报告率实测 **64 包/秒**，但每包含 3～4 个触摸采样，所以有效采样率是 200+ Hz。即使如此，如果每收到一包就把包内采样一次性拍进光标，位移依然是一跳一跳的——包与包之间仍有 15.5ms 的空白。

240Hz 独立时钟 + 时间插值把有限的采样点还原成连续轨迹。代价是 `latency = 10ms` 的缓冲（插值必须夹在两个已知点之间才不会过冲），这 10ms 对指针操作完全无感，但决定了「滑」还是「顿」。

关键设计取舍：

- **不主动外推**。采样队列末端之后钳制到最后一点，不预测未来位置。外推在丢包时会甩飞。
- **τ 随滞后量自适应**。手指快速移动时 `lagPoints` 变大 → τ 变小 → 更跟手；慢速时 τ 大 → 更稳。这比固定低通的手感好得多。
- **死区作用在速度上，且把基准推到当前位置**。只在速度低时「不输出」而不更新基准，会导致微小位移累积后突然弹出一下。正确做法是丢弃位移的同时把基准推进。
- **单 tick 位移上限 220pt**。坏包（CRC 错误或解析偏移错）可能产生巨大坐标跳变，这个上限兜底。

---

## 七、后续：DriverKit 虚拟 HID（方案 B）

只有在第五节第 2 条真的造成困扰时才值得做。

```
现状：CGEvent 注入（用户态）  → 部分程序可能忽略
目标：DriverKit 虚拟 HID 鼠标（System Extension）→ 系统视为真实鼠标
```

要点：

- 需要 **Apple Developer Program 会员**（$99/年）才能申请 DriverKit entitlement（`com.apple.developer.driverkit.family.hid.device`），自签证书不行。
- 需要一个 DriverKit DEXT target + 一个用户态 App 通过 `IOUserClient` 与它通信。
- 现有分层已经为这个切换留好口子：`TouchpadMouseService` 里注入只依赖 `tap` 和一条 `CGEvent` 构造，把这段替换成「往 IOHIDUserDevice 写报告」即可，`DS4TouchParser` 与 `TouchpadPointerEngine` 完全不用改。

另一条更省事的路：**复用 Karabiner-Elements 的虚拟鼠标 DEXT**，自己只做 DS4 读取 + 映射。代价是多一个外部依赖，且要跟着它升级。

还有方案 C（若 0x11 走不通）：用 `IOBluetooth` 直接打开 DS4 的 L2CAP 中断通道，绕过 macOS HID 层拿原始字节。这条路需要 root、要自己处理 HIDP 拆包，且会和系统 HID 驱动抢数据，只有在方案 A 失败时才考虑。

---

## 八、文件地图

| 文件 | 职责 |
|------|------|
| `Sources/DS4Mate/Services/DS4TouchParser.swift` | 报告布局判定、触摸子帧解码、CRC32。纯逻辑，零依赖 |
| `Sources/DS4Mate/Services/TouchpadPointerEngine.swift` | 插值 / 低通 / 死区 / 差分。纯算法，可单测 |
| `Sources/DS4Mate/Services/TouchpadMouseService.swift` | 240Hz 定时驱动、CGEvent 注入、屏幕夹取、设置持久化 |
| `Sources/DS4Mate/Services/HIDControllerService.swift` | `unlockFullReport()` 解锁完整报告；统一按键解析；`onTouch` 回调 |
| `tools/hid-probe/main.swift` | 独立探针，验证数据源是否真的存在 |
| `Tests/RunTests.swift` | 「DS4 报告布局」「触摸解码」「指针引擎」三组共 40 个用例 |
