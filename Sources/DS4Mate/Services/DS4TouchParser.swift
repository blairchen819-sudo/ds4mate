// DS4TouchParser.swift
// DS4 完整输入报告中的触摸板解析（纯逻辑，无 IOKit 依赖，可单测）
//
// 背景（关键）：
//   DS4 通过蓝牙连接时，**默认只发精简的 0x01 报告（10 字节）**，里面只有摇杆/按键/扳机，
//   完全没有触摸板坐标。必须先发一次 GET_REPORT(type: Feature, id: 0x02) 请求 IMU 校准数据，
//   DS4 才会把输入报告切换到完整的 0x11（78 字节），从这一刻起触摸板坐标和 IMU 才出现。
//   参考：dsremap 逆向文档 "Boot sequence / GET_REPORT 0x02" 一节。
//
// 报告布局（偏移均为「已剥离 report ID 后的 payload 内相对偏移」）：
//
//   USB 0x01 完整（64 字节）          蓝牙 0x11 完整（78 字节）
//   [0..3]   LX LY RX RY             [0]     0xC0   ← Sony 私有前缀，非标准 HIDP 头
//   [4]      dpad + 面键             [1]     0x00
//   [5]      肩键 + Share/Options     [2..5]  LX LY RX RY
//   [6]      PS + Touchpad + 计数器   ...      （所有 USB 偏移 +2）
//   [7..8]   L2 / R2 模拟
//   [9..10]  报告时间戳 (uint16 LE)
//   ...
//   [33]     触摸包计数 (uint8)
//   [34]     触摸事件计数 (uint8)
//   [35..]   触摸事件数组，每项 9 字节，USB 最多 3 项 / 蓝牙最多 4 项
//   ...
//   [最后 4 字节] CRC32
//
//   ⚠️ 蓝牙 0x11 的触摸区比「USB + 2」还要再往后一个字节，实测值见
//      DS4ReportLayout.touchEventCountOffset / touchEventsOffset（2026-11-06 抓包校准）。
//
// 单个触摸事件（9 字节，内含「上一采样」与「当前采样」两个子帧）：
//   [0]     时间戳 uint8（单位约 5.33ms，会回绕）
//   [1]     prev: bit0-6 = 触点编号, bit7 = 1 表示该槽位未激活（抬起）
//   [2]     prev X 低 8 位
//   [3]     prev 混合: 低 4 位 = X bit8-11, 高 4 位 = Y bit8-11
//   [4]     prev Y 低 8 位
//   [5]     cur : 同 prev 的编码方式
//   [6]     cur X 低 8 位
//   [7]     cur 混合
//   [8]     cur Y 低 8 位
//
//   解码：X = ((mixed & 0x0F) << 8) | xLow
//         Y = ((mixed & 0xF0) << 4) | yLow      （12 bit，范围 0...1919 / 0...942）
//
// 「一包多子帧」的真正来源：DS4 内部触摸采样率高于蓝牙报告率，所以每个事件里塞了
// prev + cur 两个采样点。单指操作时一包能拿到 2 个位置（而非 1 个），这是平滑的基础。

import Foundation

// MARK: - 公开数据模型

/// 单个触摸采样点（已归一化）
public struct TouchpadSample: Equatable {
    /// 采样时刻（单调时钟，秒）
    public let time: TimeInterval
    /// 归一化坐标 0...1（0 = 左 / 上）
    public let x: Double
    public let y: Double
    /// 事件槽位索引 0...3
    public let slot: Int
    /// 该采样点是否有效（false = 该槽位空闲/手指抬起）
    public let active: Bool
    /// DS4 触点编号（0...127，用于跟踪同一根手指）
    public let touchID: Int

    public init(time: TimeInterval, x: Double, y: Double, slot: Int, active: Bool, touchID: Int) {
        self.time = time
        self.x = x
        self.y = y
        self.slot = slot
        self.active = active
        self.touchID = touchID
    }
}

/// 一包报告解析出的触摸数据
public struct TouchpadFrame {
    /// 按时间升序排列的采样点（含 prev 子帧与 cur 子帧）
    public let samples: [TouchpadSample]
    /// 报告里声明的触摸事件数
    public let eventCount: Int
    /// 当前活跃触点数量
    public let fingerCount: Int
    /// 报告计数器（6 bit，用于检测蓝牙丢包）
    public let packetCounter: UInt8
    /// 本包到达时刻（单调时钟，秒）
    public let arrivalTime: TimeInterval

    public init(samples: [TouchpadSample], eventCount: Int, fingerCount: Int,
                packetCounter: UInt8, arrivalTime: TimeInterval = 0) {
        self.samples = samples
        self.eventCount = eventCount
        self.fingerCount = fingerCount
        self.packetCounter = packetCounter
        self.arrivalTime = arrivalTime
    }

    public var primary: TouchpadSample? {
        samples.last { $0.slot == 0 && $0.active } ?? samples.last { $0.active }
    }
}

/// 报告布局判定结果
public enum DS4ReportLayout: Equatable {
    /// 精简 0x01（10 字节）：无触摸板，说明还没发 GET_REPORT 0x02
    case limited
    /// USB 完整 0x01（64 字节）
    case usbFull
    /// 蓝牙完整 0x11（78 字节），btPrefix 表示 payload 是否带 Sony 的 0xC0 0x00 前缀
    case bluetoothFull(prefix: Bool)

    public var hasTouchpad: Bool {
        switch self {
        case .limited: return false
        case .usbFull, .bluetoothFull: return true
        }
    }

    public var maxEvents: Int {
        switch self {
        case .limited: return 0
        case .usbFull: return 3
        case .bluetoothFull: return 4
        }
    }

    /// 触摸「事件计数」字节在 payload（已剥离 report ID）内的偏移。
    ///
    /// 实测校准（2026-11-06，Mac mini + 蓝牙 DS4 0x09CC，78 字节 0x11 报告）：
    ///   payload[32] = ?          （恒为 0x00）
    ///   payload[33] = ?          （恒为 0x00）
    ///   payload[34] = 事件计数    ← eventCount 在这里
    ///   payload[35..] = 触摸事件数组，每项 9 字节，4 个槽位
    ///   payload[73..76] = CRC32
    ///
    /// 验证依据：无触摸时 4 个槽位呈现 `00 80 00 00 00 80 00 00 00` 的空闲签名，
    /// 起点严格落在绝对偏移 36/45/54/63（= payload 35/44/53/62），步长 9。
    public var touchEventCountOffset: Int {
        switch self {
        case .limited: return -1
        // USB 完整报告沿用社区文档偏移，尚未在本机实测（本机只有蓝牙链路）
        case .usbFull: return 34
        case .bluetoothFull(let prefix): return prefix ? 34 : 32
        }
    }

    /// 触摸事件数组起始偏移（payload 内）
    public var touchEventsOffset: Int {
        switch self {
        case .limited: return -1
        case .usbFull: return 35
        case .bluetoothFull(let prefix): return prefix ? 35 : 33
        }
    }

    /// 解析时真正用来定位触摸区的基准偏移
    public var touchBase: Int {
        switch self {
        case .limited: return -1
        case .usbFull: return 0
        case .bluetoothFull(let prefix): return prefix ? 2 : 0
        }
    }
}

// MARK: - 未归一化的原始触点

public struct RawTouchPoint: Equatable {
    public let active: Bool
    public let touchID: Int
    public let x: Int      // 0...1919
    public let y: Int      // 0...942

    public static let inactive = RawTouchPoint(active: false, touchID: 0, x: 0, y: 0)
}

// MARK: - 解析器

public enum DS4TouchParser {

    /// 触摸板物理分辨率
    public static let panelWidth: Double = 1920.0
    public static let panelHeight: Double = 943.0

    /// 蓝牙 0x11 报告的平均间隔（秒）。实测 64 包/秒 ≈ 15.5ms。
    /// 包内每个触摸事件的时间戳由 `packetInterval / eventCount` 推出。
    public static let defaultPacketInterval: TimeInterval = 0.0155

    // MARK: 布局判定

    /// 根据 report ID 与 payload 长度判定布局。
    /// - Parameters:
    ///   - reportID: IOHID 回调给出的 report ID（0x01 / 0x11）
    ///   - payload: 已剥离 report ID 的报告内容
    public static func layout(reportID: UInt32, payload: [UInt8]) -> DS4ReportLayout {
        // 蓝牙完整报告：78 字节，首字节 0xC0 是 Sony 私有前缀
        if reportID == 0x11 {
            if payload.count >= 76 {
                return .bluetoothFull(prefix: payload.first == 0xC0)
            }
            return .limited
        }
        // USB 完整报告：64 字节
        if reportID == 0x01 {
            if payload.count >= 60 { return .usbFull }
            // 10 字节精简报告：只有摇杆/按键/扳机
            return .limited
        }
        return .limited
    }

    /// 触摸数据在 payload 内的起始偏移
    static func touchBase(for layout: DS4ReportLayout) -> Int {
        layout.touchBase
    }

    // MARK: 主解析

    /// 解析一包完整报告中的触摸数据。
    /// - Parameters:
    ///   - payload: 已剥离 report ID 的报告内容
    ///   - layout: 布局（用 `layout(reportID:payload:)` 得到）
    ///   - arrivalTime: 报告到达时刻（单调时钟）
    ///   - packetInterval: 相邻两包报告的到达间隔（包内事件会被均匀铺开在这个区间里）
    /// - Returns: 解析结果；布局不支持触摸时返回 nil
    public static func parseTouch(payload: [UInt8],
                                  layout: DS4ReportLayout,
                                  arrivalTime: TimeInterval,
                                  packetInterval: TimeInterval = defaultPacketInterval) -> TouchpadFrame? {
        guard layout.hasTouchpad, layout.touchBase >= 0 else { return nil }
        let base = layout.touchBase

        // 事件计数在 layout.touchEventCountOffset，事件数组从 layout.touchEventsOffset 开始
        let countIndex = layout.touchEventCountOffset
        let eventsStart = layout.touchEventsOffset
        guard countIndex >= 0, eventsStart >= 0, payload.count > countIndex else { return nil }

        // 事件数不能超过布局上限，也不能超出实际可用字节（防止越界读脏数据）
        let declared = Int(payload[countIndex])
        let maxByBytes = (payload.count - eventsStart) / 9
        let eventCount = min(max(declared, 0), min(layout.maxEvents, max(0, maxByBytes)))
        guard eventCount > 0 else {
            // 没有触摸事件：返回空帧（手指已离开），调用方据此收尾
            return TouchpadFrame(samples: [], eventCount: 0, fingerCount: 0,
                                 packetCounter: packetCounter(payload: payload, base: base),
                                 arrivalTime: arrivalTime)
        }

        var samples: [TouchpadSample] = []
        var activeIDs = Set<Int>()

        // 一包里 eventCount 个事件是**时间上先后排列的采样**，不是多指槽位。
        // 实测一包 3～4 个事件，蓝牙约 64 包/秒 → 触摸采样率 ≈ 200+ Hz。
        // 时间分配：把整包展在 [arrival - eventCount*step, arrival] 上，
        // 保证最后一个采样正好落在到达时刻，前面的按 step 回溯。
        let step = max(packetInterval, 0.001) / Double(max(eventCount, 1))

        for i in 0..<eventCount {
            let e = eventsStart + i * 9
            guard e + 8 < payload.count else { break }

            let prevID = payload[e + 1]
            let curID  = payload[e + 5]

            let prevActive = (prevID & 0x80) == 0
            let curActive  = (curID  & 0x80) == 0
            let prevTouchID = Int(prevID & 0x7F)
            let curTouchID  = Int(curID  & 0x7F)

            // 本事件的时间基准：末个触点落在「该事件的末尾」
            let curTime = arrivalTime - Double(eventCount - 1 - i) * step
            let prevTime = curTime - step * 0.5

            // 实测固件只填第一个触点位（第二个 4 字节恒为 `80 00 00 00` = inactive），
            // 所以只有一个触点有效时，它就是本事件的采样，时间取 curTime；
            // 两个都有效时才区分 prev / cur 半步。
            let bothActive = prevActive && curActive

            if prevActive {
                let p = decode(payload, at: e + 2)
                samples.append(TouchpadSample(
                    time: bothActive ? prevTime : curTime,
                    x: Double(p.x) / panelWidth,
                    y: Double(p.y) / panelHeight,
                    slot: i,
                    active: true,
                    touchID: prevTouchID
                ))
                activeIDs.insert(prevTouchID)
            }

            if curActive {
                let c = decode(payload, at: e + 6)
                samples.append(TouchpadSample(
                    time: curTime,
                    x: Double(c.x) / panelWidth,
                    y: Double(c.y) / panelHeight,
                    slot: i,
                    active: true,
                    touchID: curTouchID
                ))
                activeIDs.insert(curTouchID)
            }
        }

        // 采样点排序，保证时间升序（prev 一定早于同事件的 cur）
        samples.sort { $0.time < $1.time }

        return TouchpadFrame(
            samples: samples,
            eventCount: eventCount,
            fingerCount: activeIDs.count,
            packetCounter: packetCounter(payload: payload, base: base),
            arrivalTime: arrivalTime
        )
    }

    /// 解码一个 4 字节触点（id 字节已跳过，从 X 低 8 位开始）
    ///
    /// 实测字节序（2026-11-06 真机抓包校准）：
    ///   [0] X 低 8 位
    ///   [1] 混合字节：高 4 位 = Y 低 4 位，低 4 位 = X 高 4 位
    ///   [2] Y 高 8 位
    ///
    /// ⚠️ 这里踩过坑：Y 的高位在**第 3 个字节**，低位混在第 2 个字节的高半字节。
    ///    早期实现按「Y 低位在第 3 字节」解析，导致 Y 值溢出到 3.0（面板高度只有 943）。
    /// - Parameter offset: X 低 8 位所在偏移
    static func decode(_ payload: [UInt8], at offset: Int) -> (x: Int, y: Int) {
        guard offset + 2 < payload.count else { return (0, 0) }
        let xLow  = Int(payload[offset])
        let mixed = Int(payload[offset + 1])
        let yHigh = Int(payload[offset + 2])
        let x = ((mixed & 0x0F) << 8) | xLow
        let y = (yHigh << 4) | (mixed >> 4)
        return (x, y)
    }

    /// 报告计数器（6 bit），用于检测蓝牙丢包。
    ///
    /// 位于「按钮字节组」第 3 个字节的 bit2-7：USB payload[6] / 蓝牙(带前缀) payload[8]。
    /// 实测：该字节随包递增 0x00 → 0x04 → 0x08 …，即计数器每包 +1。
    static func packetCounter(payload: [UInt8], base: Int) -> UInt8 {
        let idx = base + 6
        guard idx < payload.count else { return 0 }
        return payload[idx] >> 2
    }
}

// MARK: - CRC32（蓝牙报告完整性校验）

public enum DS4CRC32 {

    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    /// 标准 CRC-32（多项式 0x04C11DB7，反射）
    public static func compute(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// 校验蓝牙报告末尾 4 字节（小端 CRC32）。
    ///
    /// 覆盖范围随布局不同而变：
    /// - 带 0xC0 0x00 前缀：覆盖 0xA1 + reportID + payload[0...n-5]
    /// - 不带前缀：覆盖 0xA1 + reportID + payload[0...n-5]
    ///
    /// 注意：如果 CRC 计算结果与设备不符（不同固件差异），上层会关闭校验而不是丢包，
    /// 避免"以为丢包其实算法不对"导致完全无输入。
    public static func validate(payload: [UInt8], reportID: UInt8) -> Bool {
        guard payload.count >= 5 else { return false }
        let n = payload.count
        let expected = UInt32(payload[n - 4])
            | (UInt32(payload[n - 3]) << 8)
            | (UInt32(payload[n - 2]) << 16)
            | (UInt32(payload[n - 1]) << 24)

        var buffer: [UInt8] = [0xA1, reportID]
        buffer.append(contentsOf: payload[0..<(n - 4)])
        return compute(buffer[...]) == expected
    }
}
