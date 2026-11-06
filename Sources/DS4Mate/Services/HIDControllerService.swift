// HIDControllerService.swift
// 用 IOHIDManager 直接读 PS4 DualShock 4 蓝牙 HID 报告
// 绕开 GameController 框架（macOS 26 + 蓝牙 PS4 上 GameController 事件不流）
//
// ── 报告有三种布局，前 9 个有效字节结构一致 ──────────────────────────
//
//   A. 精简 0x01（10 字节）—— **蓝牙默认档位**
//      只有摇杆 / 按键 / 扳机，没有触摸板，没有 IMU。
//      这不是 macOS 的限制，是 Sony 固件的默认状态。
//
//   B. USB 完整 0x01（64 字节）
//   C. 蓝牙完整 0x11（78 字节，首字节为 0xC0 0x00 私有前缀）
//      B / C 含触摸板坐标（最多 3 / 4 个触点）与 IMU。
//
//   从 A 切到 C 的唯一开关：发一次 GET_REPORT(feature, 0x02)。
//   见 `unlockFullReport(_:)` —— 不发这一枪，触摸板坐标永远拿不到。
//
// ── 相对 payload 起始（base）的偏移 ──────────────────────────────────
//   [0..3] = LX LY RX RY（128 = 中心）
//   [4]    = dpad(0-3) | □(4) | ×(5) | ○(6) | △(7)
//   [5]    = L1(0) | R1(1) | L2(2) | R2(3) | Share(4) | Options(5) | L3(6) | R3(7)
//   [6]    = PS(0) | Touchpad(1) | 报告计数器(2-7)
//   [7]    = L2 模拟量,  [8] = R2 模拟量
//   [32]   = 触摸事件数（仅 B / C）
//   [34..] = 触摸事件数组，每项 9 字节（仅 B / C，详见 DS4TouchParser）
//
// ⚠️ 关键：IOHIDDeviceRegisterInputReportCallback 回调里的 report 缓冲区
// **含** report ID（首字节等于 reportID 参数），解析时要跳过 1 字节。
//
// ⚠️ 关键：必须把 device 挂到 **commonModes**，而不是 defaultMode。
// 菜单栏下拉（MenuBarExtra）打开时主线程 RunLoop 处于 eventTracking 模式，
// 只挂 defaultMode 的话回调完全不会触发 —— 这曾经是"按 × 没反应"的根因。

import Foundation
import IOKit
import IOKit.hid

public final class HIDControllerService {

    public static let shared = HIDControllerService()

    public private(set) var isConnected = false
    public private(set) var lastInput: (input: ControllerInput, at: Date)?
    /// 累计收到的 HID 报告数，用于自检（UI 上展示）
    public private(set) var reportCount: Int = 0
    /// 最近一次 attach 的结果说明 —— 存本地化 key + 参数，取值时才翻译，
    /// 这样切换界面语言后状态文案也会跟着变（不用等下一次 HID 事件）。
    public private(set) var statusKey: String = "hid.status.notStarted"
    private var statusArgs: [CVarArg] = []

    /// 当前语言下的状态说明（UI 直接读这个）
    public var statusMessage: String {
        statusArgs.isEmpty ? L(statusKey) : String(format: L(statusKey), arguments: statusArgs)
    }

    private func setStatus(_ key: String, _ args: CVarArg...) {
        statusKey = key
        statusArgs = args
    }

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var pressState: [String: Bool] = [:]
    private var onButton: ((ControllerInput, Bool) -> Void)?
    private var onAxis: ((ControllerInput, Double) -> Void)?
    private var onStats: ((Int) -> Void)?
    private var onTouch: ((TouchpadFrame) -> Void)?

    // MARK: - 触摸板状态（由「解锁完整报告」决定是否存在）

    /// 当前报告布局。`.limited` 表示还在精简 0x01 档位，触摸板拿不到数据
    public private(set) var reportLayout: DS4ReportLayout = .limited
    /// 是否已成功发出 GET_REPORT(feature 0x02)。
    /// 这一枪是触摸板数据的开关：没发出 → DS4 只发 10 字节精简报告。
    public private(set) var fullReportUnlocked = false
    /// GET_REPORT 的返回值（诊断用）
    public private(set) var featureReportResult: IOReturn = kIOReturnSuccess
    /// 收到的含触摸数据的报告包数
    public private(set) var touchFrameCount: Int = 0
    /// 最近一包触摸采样（调试展示）
    public private(set) var lastTouchFrame: TouchpadFrame?

    private var lastLogAt = Date.distantPast
    private var lastDPad: UInt8 = 8
    private var pendingReports = 0
    private var didWarnNoReport = false
    /// 上一次报告的单调时钟时刻 / 报告间隔的指数滑动平均
    private var lastReportTime: TimeInterval = 0
    private var reportIntervalEMA: TimeInterval = 0

    private static let reportBufferSize = 128

    public init() {}

    public func start(onButton: @escaping (ControllerInput, Bool) -> Void,
                      onAxis: @escaping (ControllerInput, Double) -> Void,
                      onTouch: ((TouchpadFrame) -> Void)? = nil,
                      onStats: ((Int) -> Void)? = nil) {
        self.onButton = onButton
        self.onAxis = onAxis
        self.onTouch = onTouch
        self.onStats = onStats
        attachManager()
    }

    public func stop() {
        if let d = device {
            IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        device = nil
        reportBuffer?.deallocate()
        reportBuffer = nil
        isConnected = false
        setStatus("hid.status.stopped")
    }

    // MARK: - Manager 装配

    private func attachManager() {
        NSLog("[DS4Mate/HID] IOHIDManager: setting up")
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // 1) 先设匹配规则（必须在 open 之前）
        let matching: [String: Any] = [kIOHIDVendorIDKey: 0x054C]  // Sony
        IOHIDManagerSetDeviceMatching(m, matching as CFDictionary)

        // 2) 注册设备插拔回调
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // 签名: (context, IOReturn, sender, IOHIDDevice)
        // 第四个参数就是匹配到的设备本身，不需要再去遍历 iterator
        IOHIDManagerRegisterDeviceMatchingCallback(m, { (context, result, sender, hidDevice) in
            let svc = Unmanaged<HIDControllerService>.fromOpaque(context!).takeUnretainedValue()
            _ = sender
            guard result == kIOReturnSuccess else { return }
            NSLog("[DS4Mate/HID] device matching callback fired")
            svc.attachDevice(hidDevice)
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(m, { (context, result, sender, hidDevice) in
            let svc = Unmanaged<HIDControllerService>.fromOpaque(context!).takeUnretainedValue()
            _ = result; _ = sender; _ = hidDevice
            svc.detachDevice()
        }, selfPtr)

        // 3) 挂 runloop —— 用 commonModes，覆盖菜单跟踪模式
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // 4) 最后 open
        let openResult = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        NSLog("[DS4Mate/HID] IOHIDManagerOpen -> 0x%08X", UInt32(bitPattern: openResult))
        if openResult != kIOReturnSuccess {
            setStatus("hid.status.managerOpenFailed", String(UInt32(bitPattern: openResult), radix: 16))
        }

        self.manager = m

        // 5) 立即扫描已连接的设备（matching 回调只对新设备触发）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.enumerateExistingDevices()
        }
    }

    /// 主动重新扫描已连接设备（供「重连手柄」按钮调用）
    public func rescan() {
        DispatchQueue.main.async { [weak self] in
            self?.enumerateExistingDevices()
        }
    }

    private func enumerateExistingDevices() {        guard let m = manager else { return }
        guard let set = IOHIDManagerCopyDevices(m) else {
            NSLog("[DS4Mate/HID] no devices snapshot")
            if !isConnected { setStatus("hid.status.noDevice") }
            return
        }
        let count = CFSetGetCount(set)
        NSLog("[DS4Mate/HID] snapshot has %d Sony device(s)", count)
        var values = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(set, &values)
        for raw in values {
            guard let raw = raw else { continue }
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(raw).takeUnretainedValue()
            let vendor = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
            NSLog("[DS4Mate/HID] found existing: vendor=0x%04X pid=0x%04X", vendor, pid)
            if vendor == 0x054C && (pid == 0x09CC || pid == 0x05C4 || pid == 0x0CE6) {
                attachDevice(dev)
            }
        }
        if !isConnected {
            setStatus("hid.status.notPS4")
        }
    }

    // MARK: - 设备装配

    private func attachDevice(_ dev: IOHIDDevice) {
        let product = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?"
        let vendor = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        NSLog("[DS4Mate/HID] attach device: vendor=0x%04X pid=0x%04X product=%@", vendor, pid, product)

        // 已 attach 过同一个设备就跳过
        if let existing = self.device, existing === dev {
            return
        }

        guard vendor == 0x054C else {
            NSLog("[DS4Mate/HID] not Sony, skip")
            return
        }
        guard pid == 0x09CC || pid == 0x05C4 || pid == 0x0CE6 else {
            NSLog("[DS4Mate/HID] pid 0x%04X not supported, skip", pid)
            setStatus("hid.status.unsupportedDevice", String(format: "0x%04X", pid))
            return
        }

        // 换设备前先清理旧的
        if let old = self.device {
            IOHIDDeviceUnscheduleFromRunLoop(old, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(old, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }

        let openResult = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        NSLog("[DS4Mate/HID] IOHIDDeviceOpen -> 0x%08X", UInt32(bitPattern: openResult))
        if openResult != kIOReturnSuccess {
            // 常见：kIOReturnExclusiveAccess(0xE00002E2) / kIOReturnNotPermitted
            setStatus("hid.status.openFailed", String(UInt32(bitPattern: openResult), radix: 16))
            NSLog("[DS4Mate/HID] open failed, abort attach")
            return
        }

        // 注册输入报告回调
        reportBuffer?.deallocate()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportBufferSize)
        buf.initialize(repeating: 0, count: Self.reportBufferSize)
        reportBuffer = buf

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDReportCallback = { (context, result, sender, type, reportID, report, reportLen) in
            let svc = Unmanaged<HIDControllerService>.fromOpaque(context!).takeUnretainedValue()
            _ = result; _ = sender; _ = type
            svc.handleReport(reportID: reportID, report: report, length: reportLen)
        }
        IOHIDDeviceRegisterInputReportCallback(dev, buf, Self.reportBufferSize, callback, selfPtr)

        // 关键：commonModes，菜单栏下拉打开时也能收到
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        self.device = dev
        self.isConnected = true
        self.setStatus("hid.status.connected", product)
        pressState.removeAll()
        didWarnNoReport = false
        fullReportUnlocked = false
        reportLayout = .limited
        touchFrameCount = 0
        NSLog("[DS4Mate/HID] PS4 attached, listening for reports (commonModes)")

        // 关键一步：请求 feature report 0x02，把 DS4 从精简 0x01 档位切到完整 0x11。
        // 不这么做，触摸板坐标永远不会出现在报告里。
        unlockFullReport(dev)

        // 3 秒后自检：如果一个报告都没收到，说明权限或驱动层有问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.reportCount == 0 && !self.didWarnNoReport {
                self.didWarnNoReport = true
                self.setStatus("hid.status.noReports")
                NSLog("[DS4Mate/HID] ⚠️ no reports received after 3s — check Input Monitoring permission")
            }
        }
    }

    // MARK: - 解锁完整报告（触摸板数据的前提）

    /// 向 DS4 请求 feature report 0x02（IMU 校准数据）。
    ///
    /// **副作用才是重点**：DS4 蓝牙默认只发 10 字节的精简 0x01 报告（只有摇杆/按键/扳机，
    /// 没有任何触摸板坐标）。收到过一次 GET_REPORT 0x02 之后，固件才切到完整 0x11 报告
    /// （78 字节，含触摸板 + IMU）。这是 Sony 的握手行为，不是 macOS 的限制。
    /// 参考 dsremap 逆向文档 "Boot sequence / GET_REPORT 0x02"。
    ///
    /// 失败常见原因：设备已被系统 GameController 独占、或 HID 权限不足。
    /// 重试策略：1s / 3s / 6s 各重试一次，共 4 次。
    private func unlockFullReport(_ dev: IOHIDDevice, attempt: Int = 0) {
        var buffer = [UInt8](repeating: 0, count: 64)
        var length = CFIndex(64)
        let result = buffer.withUnsafeMutableBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnNoMemory }
            return IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, CFIndex(0x02), base, &length)
        }
        featureReportResult = result
        NSLog("[DS4Mate/HID] GET_REPORT(feature 0x02) -> 0x%08X len=%d (尝试 %d)",
              UInt32(bitPattern: result), Int(length), attempt + 1)

        if result == kIOReturnSuccess {
            fullReportUnlocked = true
            NSLog("[DS4Mate/HID] ✅ 已请求完整报告模式，等待 0x11 报告出现")
            return
        }

        guard attempt < 3 else {
            NSLog("[DS4Mate/HID] ⚠️ 解锁完整报告失败 0x%08X — 触摸板坐标拿不到",
                  UInt32(bitPattern: result))
            setStatus("hid.status.touchpadLocked", String(UInt32(bitPattern: result), radix: 16))
            return
        }
        let delay = [1.0, 3.0, 6.0][attempt]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let d = self.device, d === dev else { return }
            self.unlockFullReport(d, attempt: attempt + 1)
        }
    }

    private func detachDevice() {
        NSLog("[DS4Mate/HID] device removed")
        if let d = device {
            IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        isConnected = false
        pressState.removeAll()
        setStatus("hid.status.disconnected")
    }

    // MARK: - 报告解析

    private func handleReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard bytes.count >= 8 else { return }

        // 只接受输入报告
        guard reportID == 0x01 || reportID == 0x11 else { return }

        reportCount += 1

        // 节流日志：约 2 秒一条
        let now = Date()
        if now.timeIntervalSince(lastLogAt) > 2.0 {
            NSLog("[DS4Mate/HID] reports: total=%d id=0x%02X len=%d head=[%@]",
                  reportCount, reportID, length,
                  bytes.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " "))
            lastLogAt = now
            onStats?(reportCount)
        }

        // 实测（macOS 26 + 蓝牙 DS4）：回调缓冲区**含** report ID。
        // 默认收到的是精简 0x01（10 字节）；发出 GET_REPORT 0x02 之后才变成完整报告。
        let hasIDPrefix = (bytes[0] == 0x01 || bytes[0] == 0x11) && UInt32(bytes[0]) == reportID
        let idSize = hasIDPrefix ? 1 : 0
        let payload = Array(bytes[idSize...])

        let layout = DS4TouchParser.layout(reportID: reportID, payload: payload)
        reportLayout = layout

        let base: Int
        switch layout {
        case .limited, .usbFull: base = 0
        case .bluetoothFull(let prefix): base = prefix ? 2 : 0
        }

        // 估算报告间隔（供触摸子帧时间戳使用）
        let uptime = ProcessInfo.processInfo.systemUptime
        if lastReportTime > 0 {
            let d = uptime - lastReportTime
            if d > 0.0008 && d < 0.2 {
                reportIntervalEMA = reportIntervalEMA == 0 ? d : reportIntervalEMA * 0.9 + d * 0.1
            }
        }
        lastReportTime = uptime

        // 按键 + 摇杆：所有布局的前 9 字节结构一致，统一解析
        parseControls(payload, base: base)

        // 触摸板：只有完整报告才带坐标
        if layout.hasTouchpad {
            let subframe = reportIntervalEMA > 0
                ? min(max(reportIntervalEMA * 0.5, 0.002), 0.02)
                : DS4TouchParser.defaultSubframeInterval
            if let frame = DS4TouchParser.parseTouch(payload: payload,
                                                    layout: layout,
                                                    arrivalTime: uptime,
                                                    subframeInterval: subframe) {
                touchFrameCount += 1
                lastTouchFrame = frame
                onTouch?(frame)
            }
        }
    }

    /// 统一的按键 / 摇杆解析。
    ///
    /// 关键事实：精简 0x01（10 字节）、USB 完整 0x01（64 字节）、蓝牙完整 0x11（78 字节）
    /// 三者的**前 9 个有效字节结构完全一致**——精简报告就是完整报告被截断的前 10 字节。
    /// 所以只用一套解析，靠 `base` 处理蓝牙的 0xC0 0x00 前缀即可。
    ///
    /// 相对 base 的偏移：
    /// [0..3] = LX LY RX RY（128 = 中心）
    /// [4]    = dpad(0-3) | □(4) | ×(5) | ○(6) | △(7)
    /// [5]    = L1(0) | R1(1) | L2(2) | R2(3) | Share(4) | Options(5) | L3(6) | R3(7)
    /// [6]    = PS(0) | Touchpad(1) | 报告计数器(2-7)
    /// [7]    = L2 模拟量
    /// [8]    = R2 模拟量
    private func parseControls(_ payload: [UInt8], base: Int) {
        guard payload.count >= base + 9 else { return }
        let b = { (i: Int) -> UInt8 in payload[base + i] }

        let lx = Double(Int(b(0)) - 128) / 128.0
        let ly = Double(Int(b(1)) - 128) / 128.0
        let rx = Double(Int(b(2)) - 128) / 128.0
        let ry = Double(Int(b(3)) - 128) / 128.0

        let btn1 = b(4)
        let btn2 = b(5)
        let btn3 = b(6)
        let l2Analog = Int(b(7))
        let r2Analog = Int(b(8))

        // D-Pad 原始 hat 值变化时打印一次，用于确认方向映射是否符合预期
        let hat = btn1 & 0x0F
        if hat != lastDPad {
            lastDPad = hat
            NSLog("[DS4Mate/HID] dpad hat=%d (8=center 0=up 2=right 4=down 6=left)", hat)
        }

        emitButtons(
            square: (btn1 & 0x10) != 0,
            cross: (btn1 & 0x20) != 0,
            circle: (btn1 & 0x40) != 0,
            triangle: (btn1 & 0x80) != 0,
            l1: (btn2 & 0x01) != 0,
            r1: (btn2 & 0x02) != 0,
            l2dig: (btn2 & 0x04) != 0,
            r2dig: (btn2 & 0x08) != 0,
            share: (btn2 & 0x10) != 0,
            options: (btn2 & 0x20) != 0,
            l3: (btn2 & 0x40) != 0,
            r3: (btn2 & 0x80) != 0,
            ps: (btn3 & 0x01) != 0,
            touchpad: (btn3 & 0x02) != 0,
            dpad: btn1 & 0x0F,
            l2Analog: l2Analog,
            r2Analog: r2Analog
        )

        emitAxis(.leftStickX, lx)
        emitAxis(.leftStickY, ly)
        emitAxis(.rightStickX, rx)
        emitAxis(.rightStickY, ry)
    }

    private func emitButtons(square: Bool, cross: Bool, circle: Bool, triangle: Bool,
                             l1: Bool, r1: Bool, l2dig: Bool, r2dig: Bool,
                             share: Bool, options: Bool, l3: Bool, r3: Bool,
                             ps: Bool, touchpad: Bool, dpad: UInt8,
                             l2Analog: Int, r2Analog: Int) {
        emit(.cross, cross)
        emit(.circle, circle)
        emit(.square, square)
        emit(.triangle, triangle)
        emit(.l1, l1)
        emit(.r1, r1)
        emit(.l3, l3)
        emit(.r3, r3)
        emit(.share, share)
        emit(.options, options)
        emit(.ps, ps)
        emit(.touchpadButton, touchpad)

        emit(.dpadUp,    dpad == 0 || dpad == 1 || dpad == 7)
        emit(.dpadDown,  dpad == 4 || dpad == 3 || dpad == 5)
        emit(.dpadLeft,  dpad == 6 || dpad == 5 || dpad == 7)
        emit(.dpadRight, dpad == 2 || dpad == 1 || dpad == 3)

        emitAnalog(.leftTriggerAxis, l2dig, analog: l2Analog)
        emitAnalog(.rightTriggerAxis, r2dig, analog: r2Analog)
    }

    private func emit(_ input: ControllerInput, _ pressed: Bool) {
        let key = input.rawValue
        let prev = pressState[key] ?? false
        if prev == pressed { return }
        pressState[key] = pressed
        if pressed {
            lastInput = (input, Date())
            NSLog("[DS4Mate/HID] button DOWN: %@", input.displayName)
        }
        onButton?(input, pressed)
    }

    private func emitAnalog(_ input: ControllerInput, _ pressed: Bool, analog: Int) {
        // 数字按键状态单独去重
        let key = input.rawValue + "_digital"
        let prev = pressState[key] ?? false
        if prev != pressed {
            pressState[key] = pressed
            if pressed {
                lastInput = (input, Date())
                NSLog("[DS4Mate/HID] trigger DOWN: %@", input.displayName)
            }
        }
        // 模拟值每次都送（由上层做死区）
        onAxis?(input, Double(analog) / 255.0)
    }

    private func emitAxis(_ input: ControllerInput, _ value: Double) {
        onAxis?(input, value)
    }
}
