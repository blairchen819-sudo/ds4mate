// DS4 HID 探针
//
// 用途：验证 macOS 上 DS4 蓝牙到底暴露了什么，以及 GET_REPORT(feature 0x02)
// 是否真的能把输入报告从精简 0x01 切到完整 0x11（触摸板数据的前提）。
//
// 编译：
//   swiftc -O -o tools/hid-probe/ds4-probe \
//       tools/hid-probe/main.swift Sources/DS4Mate/Services/DS4TouchParser.swift \
//       -framework IOKit -framework CoreFoundation
//
// 用法：
//   ./tools/hid-probe/ds4-probe                 # 普通打开，跑 15 秒
//   ./tools/hid-probe/ds4-probe --seize         # 尝试独占打开（对比用）
//   ./tools/hid-probe/ds4-probe --seconds 30    # 自定义时长
//   ./tools/hid-probe/ds4-probe --no-getreport  # 不发 0x02，观察默认档位
//
// 判读：
//   • 如果只有 id=0x01 len=10            → 还在精简档位（触摸板拿不到）
//   • 发了 0x02 之后出现 id=0x11 len>=76 → 成功，触摸板数据可用
//   • GET_REPORT 返回非 0                 → 权限或独占问题，见输出提示

import Foundation
import IOKit
import IOKit.hid

// MARK: - 参数

struct Options {
    var seize = false
    var sendGetReport = true
    var seconds: Double = 15
    var dumpDescriptor = true
    var verboseDescriptor = false
}

func parseArgs() -> Options {
    var o = Options()
    let a = CommandLine.arguments
    var i = 1
    while i < a.count {
        switch a[i] {
        case "--seize": o.seize = true
        case "--no-getreport": o.sendGetReport = false
        case "--seconds":
            i += 1
            if i < a.count, let v = Double(a[i]) { o.seconds = v }
        case "--no-descriptor": o.dumpDescriptor = false
        case "--verbose-descriptor": o.verboseDescriptor = true
        case "-h", "--help":
            print("""
            用法: ds4-probe [--seize] [--no-getreport] [--seconds N] [--no-descriptor]

              --seize          用 kIOHIDOptionsTypeSeizeDevice 独占打开（需要 root）
              --no-getreport   不发 GET_REPORT(0x02)，观察 DS4 默认档位
              --seconds N      采集时长，默认 15 秒
              --no-descriptor  不打印 report descriptor
            """)
            exit(0)
        default:
            break
        }
        i += 1
    }
    return o
}

let opts = parseArgs()

// MARK: - 统计

final class Stats {
    var packetsByID: [UInt32: Int] = [:]
    var lengthsByID: [UInt32: Set<Int>] = [:]
    var touchFrames = 0
    var touchSamples = 0
    var firstTouchSample: TouchpadSample?
    var lastTouchSample: TouchpadSample?
    var layoutsSeen: Set<String> = []
    var printedReports = 0
    private var totalPackets = 0

    func record(reportID: UInt32, length: Int, layout: DS4ReportLayout, frame: TouchpadFrame?) {
        packetsByID[reportID, default: 0] += 1
        lengthsByID[reportID, default: []].insert(length)
        switch layout {
        case .limited: layoutsSeen.insert("limited(0x01/10B)")
        case .usbFull: layoutsSeen.insert("usbFull(0x01/64B)")
        case .bluetoothFull(let p): layoutsSeen.insert("btFull(0x11\(p ? "+0xC0" : ""))")
        }
        if let f = frame {
            touchFrames += 1
            touchSamples += f.samples.count
            if let s = f.samples.first { if firstTouchSample == nil { firstTouchSample = s } }
            if let l = f.samples.last { lastTouchSample = l }
        }
        totalPackets += 1
    }

    func summary() {
        print("")
        print("──────── 汇总 ────────")
        for (id, n) in packetsByID.sorted(by: { $0.key < $1.key }) {
            let lens = (lengthsByID[id] ?? []).sorted().map(String.init).joined(separator: "/")
            print(String(format: "report 0x%02X : %6d 包, 长度 %@", id, n, lens))
        }
        print("布局: \(layoutsSeen.sorted().joined(separator: ", "))")
        print("含触摸的包: \(touchFrames), 采样点: \(touchSamples)")
        if let f = firstTouchSample, let l = lastTouchSample {
            print(String(format: "首个触点 (%.3f, %.3f) → 末个 (%.3f, %.3f)",
                         f.x, f.y, l.x, l.y))
        }
        print("总包数: \(totalPackets)")
        if packetsByID[0x11] == nil && packetsByID[0x01] != nil {
            print("")
            print("⚠️  没收到 0x11 完整报告 —— 触摸板坐标不可用。")
            print("   若已发 0x02 仍如此，说明 macOS 的 HID 层没把 0x11 投递上来，")
            print("   需要走 IOBluetooth 直接读 L2CAP 中断通道（方案 C）。")
        }
    }
}

let stats = Stats()

// MARK: - 描述符解析

/// 从 report descriptor 里扫出所有 Report ID item (0x85)
func scanReportIDs(_ descriptor: [UInt8]) -> [UInt8] {
    var ids: [UInt8] = []
    var i = 0
    while i < descriptor.count {
        let prefix = descriptor[i]
        guard prefix != 0xFE else { break }   // long item，跳过
        let sizeCode = Int(prefix & 0x03)
        let size = sizeCode == 3 ? 4 : sizeCode
        let tag = prefix & 0xFC
        if tag == 0x84 && size >= 1 && i + 1 < descriptor.count {   // Report ID
            ids.append(descriptor[i + 1])
        }
        i += 1 + size
    }
    return ids
}

// MARK: - 设备处理

final class Probe {
    let device: IOHIDDevice
    let options: Options
    var buffer: UnsafeMutablePointer<UInt8>
    let bufferSize = 256
    var getReportResult: IOReturn = kIOReturnSuccess

    init(device: IOHIDDevice, options: Options) {
        self.device = device
        self.options = options
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit { buffer.deallocate() }

    func describe() {
        func prop(_ key: String) -> Any? {
            IOHIDDeviceGetProperty(device, key as CFString)
        }
        let product = prop(kIOHIDProductKey) as? String ?? "?"
        let vendor = prop(kIOHIDVendorIDKey) as? Int ?? 0
        let pid = prop(kIOHIDProductIDKey) as? Int ?? 0
        let transport = prop(kIOHIDTransportKey) as? String ?? "?"
        let usagePage = prop(kIOHIDPrimaryUsagePageKey) as? Int ?? 0
        let usage = prop(kIOHIDPrimaryUsageKey) as? Int ?? 0
        let maxIn = prop(kIOHIDMaxInputReportSizeKey) as? Int ?? 0
        let maxFeature = prop(kIOHIDMaxFeatureReportSizeKey) as? Int ?? 0
        let serial = prop(kIOHIDSerialNumberKey) as? String ?? "-"

        print("")
        print("════ 设备 ════")
        print("  名称      : \(product)")
        print(String(format: "  VID/PID   : 0x%04X / 0x%04X", vendor, pid))
        print("  传输      : \(transport)")
        print("  序列号    : \(serial)")
        print(String(format: "  usage     : page 0x%04X / id 0x%04X", usagePage, usage))
        print("  最大输入  : \(maxIn) B,  最大 feature: \(maxFeature) B")

        if options.dumpDescriptor, let data = prop(kIOHIDReportDescriptorKey) as? Data {
            let bytes = [UInt8](data)
            let ids = scanReportIDs(bytes)
            print("  描述符    : \(bytes.count) B")
            print("  Report ID : " + (ids.isEmpty ? "（无）" : ids.map { String(format: "0x%02X", $0) }.joined(separator: ", ")))
            if opts.verboseDescriptor {
                print("  描述符 hex: " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
            }
        }
    }

    func open() -> Bool {
        let flag = options.seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone
        let r = IOHIDDeviceOpen(device, IOOptionBits(flag))
        let name = options.seize ? "seize" : "normal"
        print(String(format: "  打开(%@) → 0x%08X", name, UInt32(bitPattern: r)))
        if r != kIOReturnSuccess {
            switch r {
            case kIOReturnExclusiveAccess:
                print("    ↳ 设备已被其他进程独占")
            case kIOReturnNotPermitted, kIOReturnNotPrivileged:
                print("    ↳ 权限不足：seize 需要 root；普通读取需要「输入监控」权限")
            default:
                print("    ↳ 失败，继续尝试其他方式")
            }
            return false
        }
        return true
    }

    func requestFullReport() {
        var buf = [UInt8](repeating: 0, count: 64)
        var len = CFIndex(64)
        let r = buf.withUnsafeMutableBufferPointer { p -> IOReturn in
            guard let base = p.baseAddress else { return kIOReturnNoMemory }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(0x02), base, &len)
        }
        getReportResult = r
        print(String(format: "  GET_REPORT(feature 0x02) → 0x%08X, 返回 %d 字节", UInt32(bitPattern: r), Int(len)))
        if r == kIOReturnSuccess {
            let head = buf.prefix(min(Int(len), 16)).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("    校准数据头部: \(head)")
            print("    ✅ 已请求完整报告模式，观察后续是否出现 0x11")
        } else {
            print("    ⚠️ 请求失败，DS4 不会切到完整报告 —— 触摸板拿不到数据")
        }
    }

    func listen() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDReportCallback = { ctx, result, sender, type, reportID, report, len in
            guard let ctx = ctx else { return }
            let probe = Unmanaged<Probe>.fromOpaque(ctx).takeUnretainedValue()
            _ = result; _ = sender; _ = type
            probe.handle(reportID: reportID, report: report, length: len)
        }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, callback, selfPtr)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    private var lastPrint = Date.distantPast

    func handle(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let n = Int(length)
        let bytes = Array(UnsafeBufferPointer(start: report, count: n))

        // 回调缓冲区通常含 report ID（首字节 == reportID）
        let hasID = !bytes.isEmpty && UInt32(bytes[0]) == reportID
        let payload = hasID ? Array(bytes[1...]) : bytes
        let layout = DS4TouchParser.layout(reportID: reportID, payload: payload)
        let frame = DS4TouchParser.parseTouch(payload: payload,
                                              layout: layout,
                                              arrivalTime: Date().timeIntervalSince1970)
        stats.record(reportID: reportID, length: n, layout: layout, frame: frame)

        // 前 3 秒全量打印，之后按 0.5s 节流
        let elapsed = Date().timeIntervalSince(startTime)
        let shouldPrint = elapsed < 3.0 || Date().timeIntervalSince(lastPrint) > 0.5
        guard shouldPrint else { return }
        lastPrint = Date()

        let head = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        print(String(format: "[%6.2fs] id=0x%02X len=%3d %@ | %@",
                     elapsed, reportID, n, head, "\(layout)"))

        if let f = frame, let p = f.primary {
            print(String(format: "          触摸: 事件%d 手指%d  slot0=(%.4f, %.4f) 点击数=%d",
                         f.eventCount, f.fingerCount, p.x, p.y, f.samples.count))
        }
    }
}

// MARK: - 主流程

let startTime = Date()
var probes: [Probe] = []

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x054C] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let managerOpen = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print(String(format: "IOHIDManagerOpen → 0x%08X", UInt32(bitPattern: managerOpen)))

guard let deviceSet = IOHIDManagerCopyDevices(manager) else {
    print("没有找到任何 Sony 设备。请先在系统蓝牙里连接手柄。")
    exit(1)
}
let count = CFSetGetCount(deviceSet)
print("发现 \(count) 个 Sony 设备")

if count == 0 {
    print("""

    ⚠️ 没有 Sony 设备。
       1. 按住 Share + PS 让手柄进入配对模式
       2. 系统设置 → 蓝牙 → 配对手柄
       3. 重新运行本探针
    """)
    exit(1)
}

var values = [UnsafeRawPointer?](repeating: nil, count: count)
CFSetGetValues(deviceSet, &values)

for raw in values {
    guard let raw = raw else { continue }
    let dev = Unmanaged<IOHIDDevice>.fromOpaque(raw).takeUnretainedValue()
    let probe = Probe(device: dev, options: opts)
    probe.describe()
    if probe.open() {
        if opts.sendGetReport { probe.requestFullReport() }
        probe.listen()
        probes.append(probe)
    }
}

if probes.isEmpty {
    print("""

    ⚠️ 没有任何设备成功打开。
       普通模式失败 → 打开「系统设置 → 隐私与安全性 → 输入监控」，勾选终端 / 你的 App
       seize 模式失败 → 需要 sudo 运行
    """)
    exit(2)
}

print("")
print("开始采集 \(Int(opts.seconds)) 秒 —— 现在请：")
print("  ① 摇一下左摇杆（确认基础报告在流）")
print("  ② 在触摸板上慢慢划一条斜线（观察是否有触摸坐标输出）")
print("")

let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
    if Date().timeIntervalSince(startTime) >= opts.seconds {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}
RunLoop.current.add(timer, forMode: .common)
CFRunLoopRun()

stats.summary()
print("")
print("GET_REPORT(0x02) 结果: " + String(format: "0x%08X", UInt32(bitPattern: probes.first?.getReportResult ?? 0)))
exit(0)
