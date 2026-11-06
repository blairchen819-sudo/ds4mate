// TouchpadMouseService.swift
// 触摸板 → 系统鼠标指针 的编排层
//
// 职责边界的划分：
//   HIDControllerService  → 拿到原始报告，解析成 TouchpadFrame（含多子帧采样）
//   TouchpadPointerEngine → 纯算法：插值 / 低通 / 死区 / 差分（可单测）
//   本文件                → 240Hz 定时驱动 + CGEvent 注入 + 屏幕边界与位置校准
//
// 为什么用 240Hz 而不是「收到报告就移动」：
//   蓝牙 DS4 报告率实测 60-100Hz，如果每包只移动一次，指针就是一格一格的台阶。
//   240Hz 独立时钟 + 时间插值，把有限的采样点还原成连续轨迹——这是「顺滑」的来源。

import Foundation
import CoreGraphics
import AppKit

public final class TouchpadMouseService {

    public static let shared = TouchpadMouseService()

    public let engine = TouchpadPointerEngine()

    /// 输出事件注入点。
    /// `.cghidEventTap` 比 `.cgSessionEventTap` 更接近硬件层，被全屏/独占渲染程序吞掉的概率更低；
    /// 若某些程序仍不认，只能上 DriverKit 虚拟 HID（见文档 roadmap）。
    public var tap: CGEventTapLocation = .cghidEventTap

    private var timer: DispatchSourceTimer?
    private var shadowPosition: CGPoint?
    private var wasTracking = false
    private var lastCalibration: TimeInterval = 0

    // 诊断
    public private(set) var isRunning = false
    public private(set) var outputHz: Double = 0
    public private(set) var totalMovedPoints: Double = 0
    private var tickCount = 0
    private var rateWindowStart: TimeInterval = 0

    private var screenUnionCache: CGRect = .zero
    private var screenUnionCacheAt: TimeInterval = 0

    private init() {
        // 恢复上次保存的手感参数（启停由 ControllerService 按用户开关决定）
        loadPersistedConfig()
    }

    // MARK: - 配置

    public var config: PointerConfig {
        get { engine.config }
        set { engine.config = newValue }
    }

    /// 触摸板被按下（click）时是否冻结指针。
    /// 默认关闭：按下拖动（选中文字）是常规操作，冻结会让它失效；
    /// 按下瞬间的位置抖动由速度死区吸收。
    public var freezeWhileClicking = false

    // MARK: - 生命周期

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        engine.reset()
        shadowPosition = nil
        wasTracking = false
        tickCount = 0
        rateWindowStart = ProcessInfo.processInfo.systemUptime

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        t.schedule(deadline: .now(),
                   repeating: .nanoseconds(4_166_667),   // 240Hz
                   leeway: .nanoseconds(250_000))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
        NSLog("[DS4Mate/Touchpad] 指针输出已启动 @240Hz tap=%d", tap.rawValue)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        engine.reset()
        shadowPosition = nil
        NSLog("[DS4Mate/Touchpad] 指针输出已停止")
    }

    // MARK: - 输入

    public func ingest(_ frame: TouchpadFrame) {
        guard isRunning else { return }
        engine.ingest(frame, arrivalTime: frame.arrivalTime)
    }

    /// 触摸板物理按键状态（由 ControllerService 转发）
    public func setPressed(_ pressed: Bool) {
        engine.isFrozen = freezeWhileClicking && pressed
    }

    // MARK: - 输出循环

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let union = screenUnion()
        let delta = engine.tick(now: now, screenSize: union.size)

        // 触摸开始时把影子位置同步到真实光标：
        // 修掉「上次注入被某个 App 吞掉」或「中途用过真实鼠标」造成的位置偏差。
        if engine.isTracking && !wasTracking {
            shadowPosition = CGEvent(source: nil)?.location
            lastCalibration = now
        }
        wasTracking = engine.isTracking

        if delta.dx == 0 && delta.dy == 0 {
            // 静止时顺便校准，成本为零且能持续纠偏
            if engine.isTracking && now - lastCalibration > 3.0 {
                shadowPosition = CGEvent(source: nil)?.location
                lastCalibration = now
            }
            accountRate(now)
            return
        }

        let current = shadowPosition ?? CGEvent(source: nil)?.location ?? .zero
        var target = CGPoint(x: current.x + delta.dx, y: current.y + delta.dy)

        // 夹到屏幕联合区域，避免指针被推到不存在的坐标
        target.x = min(max(target.x, union.minX + 0.5), union.maxX - 0.5)
        target.y = min(max(target.y, union.minY + 0.5), union.maxY - 0.5)

        guard let move = CGEvent(mouseEventSource: nil,
                                 mouseType: .mouseMoved,
                                 mouseCursorPosition: target,
                                 mouseButton: .left) else { return }

        // 同时写入 delta 字段：部分程序（尤其游戏 / 渲染器）只读 delta 不读绝对坐标
        move.setIntegerValueField(.mouseEventDeltaX, value: Int64(target.x - current.x))
        move.setIntegerValueField(.mouseEventDeltaY, value: Int64(target.y - current.y))
        move.post(tap: tap)

        totalMovedPoints += hypot(target.x - current.x, target.y - current.y)
        shadowPosition = target
        accountRate(now)
    }

    private func accountRate(_ now: TimeInterval) {
        tickCount += 1
        let span = now - rateWindowStart
        if span >= 1.0 {
            outputHz = Double(tickCount) / span
            tickCount = 0
            rateWindowStart = now
        }
    }

    // MARK: - 屏幕几何

    /// 所有活动显示器的联合区域（Quartz 坐标系，原点左上）。
    /// 必须用 CGDisplayBounds 而不是 NSScreen.frame —— 后者是左下原点，两套坐标系混用会导致边界判断错位。
    private func screenUnion() -> CGRect {
        let now = ProcessInfo.processInfo.systemUptime
        if screenUnionCache != .zero && now - screenUnionCacheAt < 2.0 {
            return screenUnionCache
        }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var union = CGRect.zero
        if count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetActiveDisplayList(count, &ids, &count) == .success {
                for i in 0..<Int(count) {
                    let b = CGDisplayBounds(ids[i])
                    union = union == .zero ? b : union.union(b)
                }
            }
        }
        if union == .zero {
            union = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        screenUnionCache = union
        screenUnionCacheAt = now
        return union
    }
}

// MARK: - 设置持久化

/// 触摸板鼠标的开关与手感参数，落在 UserDefaults。
/// 用 UserDefaults 而不是 Profile，因为它是「全局输入通道」而非某套键位映射的一部分。
extension TouchpadMouseService {

    private static let keyEnabled     = "ds4.touchpadMouse.enabled"
    private static let keySensitivity = "ds4.touchpadMouse.sensitivity"
    private static let keySmoothing   = "ds4.touchpadMouse.smoothing"
    private static let keyDeadzone    = "ds4.touchpadMouse.deadzone"

    /// 用户是否开启了「触摸板当鼠标」。
    /// 开启后：触摸板滑动移动指针，触摸板按下 = 鼠标左键（不再触发原有映射）。
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.keyEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.keyEnabled)
            if newValue {
                loadPersistedConfig()
                start()
            } else {
                stop()
            }
        }
    }

    /// 从 UserDefaults 读出手感参数（未设置过的项保留默认值）
    public func loadPersistedConfig() {
        let d = UserDefaults.standard
        var c = engine.config
        if d.object(forKey: Self.keySensitivity) != nil {
            c.sensitivity = min(max(d.double(forKey: Self.keySensitivity), 0.5), 8.0)
        }
        if d.object(forKey: Self.keySmoothing) != nil {
            c.smoothing = min(max(d.double(forKey: Self.keySmoothing), 0.0), 1.0)
        }
        if d.object(forKey: Self.keyDeadzone) != nil {
            c.deadzoneSpeed = min(max(d.double(forKey: Self.keyDeadzone), 0.0), 60.0)
        }
        engine.config = c
    }

    /// 把手感参数写回 UserDefaults
    public func persistConfig() {
        let d = UserDefaults.standard
        d.set(engine.config.sensitivity, forKey: Self.keySensitivity)
        d.set(engine.config.smoothing, forKey: Self.keySmoothing)
        d.set(engine.config.deadzoneSpeed, forKey: Self.keyDeadzone)
    }
}
