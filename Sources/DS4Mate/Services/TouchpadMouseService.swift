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

    /// 双指手势识别（滚动 / 捏合缩放）
    public let gesture = TwoFingerGestureRecognizer()

    /// 输出事件注入点。
    /// `.cghidEventTap` 比 `.cgSessionEventTap` 更接近硬件层，被全屏/独占渲染程序吞掉的概率更低；
    /// 若某些程序仍不认，只能上 DriverKit 虚拟 HID（见文档 roadmap）。
    public var tap: CGEventTapLocation = .cghidEventTap

    private var timer: DispatchSourceTimer?
    private var shadowPosition: CGPoint?
    private var wasTracking = false
    private var lastCalibration: TimeInterval = 0

    /// 上一帧是否为多指。用于在「双指 → 单指」切换时重置指针基准，
    /// 否则指针会从双指前的位置突然跳到新位置。
    private var wasMultiTouch = false

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
        gesture.reset()
        wasMultiTouch = false
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
        gesture.reset()
        wasMultiTouch = false
        shadowPosition = nil
        NSLog("[DS4Mate/Touchpad] 指针输出已停止")
    }

    // MARK: - 输入

    /// 喂入一包解析结果，按手指数分流：
    /// - 单指 → 指针引擎（滑动手感管线）
    /// - 多指 → 手势识别（滚动 / 缩放），并把指针完全冻结
    public func ingest(_ frame: TouchpadFrame) {
        guard isRunning else { return }

        if frame.isMultiTouch {
            // 进入双指：立刻清空指针状态，避免双指前的位置残留导致双指结束后跳变
            if !wasMultiTouch {
                engine.reset()
                wasMultiTouch = true
            }
            emitGesture(gesture.ingest(frame.fingers))
            return
        }

        if wasMultiTouch {
            // 退出双指：重新建立指针基准（第一帧只建立基准，不产生位移）
            engine.reset()
            wasMultiTouch = false
        }
        gesture.reset()
        engine.ingest(frame, arrivalTime: frame.arrivalTime)
    }

    // MARK: - 手势输出

    /// 把双指手势翻译成系统事件。
    ///
    /// 缩放用 ⌘= / ⌘- 热键而不是真正的 magnify 手势事件：
    /// macOS 的 magnify 事件走私有事件类型（NSEventTypeMagnify 在 CGEvent 层没有公开构造函数），
    /// 伪造私有事件在不同系统版本上行为不可控。⌘= / ⌘- 是绝大多数 App（浏览器、
    /// 预览、Office、Figma、Sketch）都认的通用放大/缩小快捷键，稳定性远高于私有事件。
    /// 代价是在 Finder 这类把 ⌘= 绑成「打开」的 App 里会误触，所以缩放默认关闭力度较弱
    /// （需要明显张开/收拢才触发一档）。
    private func emitGesture(_ out: TwoFingerGestureOutput) {
        guard out.isActive else { return }

        if out.isScrolling {
            EventSynthesizer.shared.scroll(dx: out.scrollX, dy: out.scrollY)
        }

        if out.isZooming {
            let steps = min(abs(out.zoomSteps), 3)   // 单帧最多 3 档，防坏包连发
            let keyCode = out.zoomSteps > 0 ? 24 : 27   // 24 = '=' 放大, 27 = '-' 缩小
            for _ in 0..<steps {
                EventSynthesizer.shared.keyPress(keyCode: keyCode, modifiers: .maskCommand)
            }
        }
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

    // 双指手势
    private static let keyTwoFingerOn     = "ds4.touchpadMouse.twoFingerEnabled"
    private static let keyScrollScale     = "ds4.touchpadMouse.scrollScale"
    private static let keyZoomScale       = "ds4.touchpadMouse.zoomScale"
    private static let keyInvertScroll    = "ds4.touchpadMouse.invertScroll"

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

        var g = gesture.config
        if d.object(forKey: Self.keyTwoFingerOn) != nil {
            g.isEnabled = d.bool(forKey: Self.keyTwoFingerOn)
        }
        if d.object(forKey: Self.keyScrollScale) != nil {
            g.scrollScale = min(max(d.double(forKey: Self.keyScrollScale), 400.0), 8000.0)
        }
        if d.object(forKey: Self.keyZoomScale) != nil {
            g.zoomScale = min(max(d.double(forKey: Self.keyZoomScale), 0.2), 4.0)
        }
        if d.object(forKey: Self.keyInvertScroll) != nil {
            g.invertScroll = d.bool(forKey: Self.keyInvertScroll)
        }
        gesture.config = g
    }

    /// 把手感参数写回 UserDefaults
    public func persistConfig() {
        let d = UserDefaults.standard
        d.set(engine.config.sensitivity, forKey: Self.keySensitivity)
        d.set(engine.config.smoothing, forKey: Self.keySmoothing)
        d.set(engine.config.deadzoneSpeed, forKey: Self.keyDeadzone)

        d.set(gesture.config.isEnabled, forKey: Self.keyTwoFingerOn)
        d.set(gesture.config.scrollScale, forKey: Self.keyScrollScale)
        d.set(gesture.config.zoomScale, forKey: Self.keyZoomScale)
        d.set(gesture.config.invertScroll, forKey: Self.keyInvertScroll)
    }
}
