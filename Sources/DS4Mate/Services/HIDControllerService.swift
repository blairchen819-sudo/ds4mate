// HIDControllerService.swift
// 用 IOHIDManager 直接读 PS4 DualShock 4 蓝牙 HID 报告
// 绕开 GameController 框架（macOS 26 + 蓝牙 PS4 上 GameController 事件不流）
//
// DS4 蓝牙完整报告 0x11（含 report ID，共 79 字节）：
//   [0]   = 0x11 (report ID)
//   [1]   = LX (0-255, 128=center)
//   [2]   = LY
//   [3]   = RX
//   [4]   = RY
//   [5]   = D-Pad hat (低4位) | L2 digital(4) | R2 digital(5) | L1(6) | R1(7)
//   [6]   = Square(0) | Cross(1) | Circle(2) | Triangle(3) | Share(4) | Options(5) | L3(6) | R3(7)
//   [7]   = PS(0) | Touchpad(1) | counter
//   [8-9] = L2 analog (0-255, LE)
//   [10-11] = R2 analog (0-255, LE)
//
// ⚠️ 关键：IOHIDDeviceRegisterInputReportCallback 回调里的 report 缓冲区
// **不含 report ID**（report ID 单独作为参数传入）。所以真实偏移要 -1。
// 本实现用「首字节是否为 0x11」自适应判断，两种情形都能处理。
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
    /// 最近一次 attach 的结果说明，用于 UI 提示
    public private(set) var statusMessage: String = "未启动"

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var pressState: [String: Bool] = [:]
    private var onButton: ((ControllerInput, Bool) -> Void)?
    private var onAxis: ((ControllerInput, Double) -> Void)?
    private var onStats: ((Int) -> Void)?

    private var lastLogAt = Date.distantPast
    private var lastDPad: UInt8 = 8
    private var pendingReports = 0
    private var didWarnNoReport = false

    private static let reportBufferSize = 128

    public init() {}

    public func start(onButton: @escaping (ControllerInput, Bool) -> Void,
                      onAxis: @escaping (ControllerInput, Double) -> Void,
                      onStats: ((Int) -> Void)? = nil) {
        self.onButton = onButton
        self.onAxis = onAxis
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
        statusMessage = "已停止"
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
            statusMessage = "IOHIDManager 打开失败 (0x\(String(UInt32(bitPattern: openResult), radix: 16)))"
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
            if !isConnected { statusMessage = "未发现 Sony 设备" }
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
            statusMessage = "找到了 Sony 设备但不是 PS4 手柄（pid 不匹配）"
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
            statusMessage = "设备 \(String(format: "0x%04X", pid)) 暂不支持"
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
            statusMessage = "手柄打开失败 (0x\(String(UInt32(bitPattern: openResult), radix: 16)))，可能需要在「隐私与安全性 → 输入监控」里允许"
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
        self.statusMessage = "已连接：\(product)"
        pressState.removeAll()
        didWarnNoReport = false
        NSLog("[DS4Mate/HID] PS4 attached, listening for reports (commonModes)")

        // 3 秒后自检：如果一个报告都没收到，说明权限或驱动层有问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.reportCount == 0 && !self.didWarnNoReport {
                self.didWarnNoReport = true
                self.statusMessage = "已打开手柄但收不到数据，请检查「输入监控」权限"
                NSLog("[DS4Mate/HID] ⚠️ no reports received after 3s — check Input Monitoring permission")
            }
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
        statusMessage = "手柄已断开"
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

        // 实测（macOS 26 + 蓝牙 DS4）：回调缓冲区**含** report ID，
        // 且系统给的是精简的 0x01（10 字节），不是传统完整 0x11（78 字节）。
        let hasIDPrefix = (bytes[0] == 0x01 || bytes[0] == 0x11) && UInt32(bytes[0]) == reportID
        let o = hasIDPrefix ? 1 : 0

        switch reportID {
        case 0x01:
            parseSimpleReport(bytes, offset: o)
        case 0x11:
            parseFullReport(bytes, offset: o)
        default:
            break
        }
    }

    /// 精简报告 0x01（10 字节，含 ID）
    /// [0]=ID [1]=LX [2]=LY [3]=RX [4]=RY
    /// [5]=dpad(0-3) | □(4) | ×(5) | ○(6) | △(7)
    /// [6]=L1(0) | R1(1) | L2(2) | R2(3) | Share(4) | Options(5) | L3(6) | R3(7)
    /// [7]=PS(0) | Touchpad(1)
    /// [8]=L2 analog  [9]=R2 analog
    private func parseSimpleReport(_ bytes: [UInt8], offset: Int) {
        guard bytes.count >= offset + 9 else { return }
        let b = { (i: Int) -> UInt8 in bytes[offset + i] }

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

    /// 完整报告 0x11（78 字节，含 ID）
    /// [1]=LX [2]=LY [3]=RX [4]=RY
    /// [5]=dpad(0-3) | L2dig(4) | R2dig(5) | L1(6) | R1(7)
    /// [6]=□(0) | ×(1) | ○(2) | △(3) | Share(4) | Options(5) | L3(6) | R3(7)
    /// [7]=PS(0) | Touchpad(1)
    /// [8]=L2 analog  [10]=R2 analog
    private func parseFullReport(_ bytes: [UInt8], offset: Int) {
        guard bytes.count >= offset + 10 else { return }
        let b = { (i: Int) -> UInt8 in bytes[offset + i] }

        let lx = Double(Int(b(0)) - 128) / 128.0
        let ly = Double(Int(b(1)) - 128) / 128.0
        let rx = Double(Int(b(2)) - 128) / 128.0
        let ry = Double(Int(b(3)) - 128) / 128.0

        let dpadAndLR = b(4)
        let faceAndSide = b(5)
        let centerAndPad = b(6)
        let l2Analog = Int(b(7))
        let r2Analog = Int(b(9))

        emitButtons(
            square: (faceAndSide & 0x01) != 0,
            cross: (faceAndSide & 0x02) != 0,
            circle: (faceAndSide & 0x04) != 0,
            triangle: (faceAndSide & 0x08) != 0,
            l1: (dpadAndLR & 0x40) != 0,
            r1: (dpadAndLR & 0x80) != 0,
            l2dig: (dpadAndLR & 0x10) != 0,
            r2dig: (dpadAndLR & 0x20) != 0,
            share: (faceAndSide & 0x10) != 0,
            options: (faceAndSide & 0x20) != 0,
            l3: (faceAndSide & 0x40) != 0,
            r3: (faceAndSide & 0x80) != 0,
            ps: (centerAndPad & 0x01) != 0,
            touchpad: (centerAndPad & 0x02) != 0,
            dpad: dpadAndLR & 0x0F,
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
