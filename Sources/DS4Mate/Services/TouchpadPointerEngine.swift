// TouchpadPointerEngine.swift
// 触摸板 → 指针位移的「手感管线」（纯逻辑，无 IO/Syscall，可单测）
//
// 处理链：
//   DS4 报告（~60-100Hz，每包含 prev/cur 两个子帧）
//     ↓ ingest 入队
//   采样队列（保留最近若干帧）
//     ↓ tick（240Hz 定时驱动），按「now - latency」查询
//   时间线性插值  → 得到当前位置 target
//     ↓ 速度自适应一阶低通（τ 随滞后量变化：慢速更稳、快速更跟手）
//   filtered 位置
//     ↓ 差分 × 灵敏度 × 屏幕尺寸
//   delta（像素点）
//     ↓ 速度死区
//   输出给 CGEvent
//
// 为什么需要 latency：插值必须「夹在两个已知采样点之间」才不会过冲。
// 留 1 个报告间隔的缓冲，代价是 ~10ms 延迟，换来的是轨迹连续、无台阶感。
// 这 10ms 对指针操作完全无感，但决定了「滑」还是「顿」。

import Foundation
import CoreGraphics

// MARK: - 配置

public struct PointerConfig: Equatable {
    /// 灵敏度：手指滑满触摸板宽度 = 屏幕上移动多少屏宽
    public var sensitivity: Double = 2.6
    /// 平滑强度 0...1。0 = 原始跟手（有台阶），1 = 极顺但明显滞后
    public var smoothing: Double = 0.45
    /// 速度死区（点/秒）：低于该速度的微小抖动直接丢弃，防止静止时指针缓慢漂移
    public var deadzoneSpeed: Double = 4.0
    /// 插值缓冲延迟（秒）。一般取一个蓝牙报告间隔
    public var latency: TimeInterval = 0.010
    /// 低速精修增益：慢速移动时的位移缩放，<1 让精细定位更可控
    public var lowSpeedGain: Double = 0.82
    /// 低速判定阈值（点/秒），超过则增益恢复到 1.0
    public var lowSpeedThreshold: Double = 260.0
    /// 单次 tick 允许的最大位移（点），防止坏包把指针甩飞
    public var maxStepPerTick: Double = 220.0

    public init() {}
}

// MARK: - 引擎

public final class TouchpadPointerEngine {

    public var config = PointerConfig()

    /// 当前是否处于触摸追踪状态（手指在板上）
    public private(set) var isTracking = false
    /// 冻结输出（例如按下触摸板点击时，手指位置会抖，冻结可避免拖动失真）
    public var isFrozen = false

    // 采样队列
    private var samples: [TouchpadSample] = []
    /// 队列保留时长：超过这个时间的历史采样丢弃
    private let historyWindow: TimeInterval = 0.25

    // 滤波状态
    private var filtered: CGPoint?          // 滤波后的归一化绝对位置
    private var lastEmitted: CGPoint?       // 上次真正输出的归一化位置
    private var lastTickTime: TimeInterval?
    private var lastTarget: CGPoint?
    private var lastTargetTime: TimeInterval?

    /// 当前正在追踪的触点编号。
    ///
    /// DS4 每次「抬起 → 重新落下」都会分配一个新编号（0...127 循环）。
    /// 编号变化是「板面瞬移」最可靠的信号：用户把手指从板上抬起来、换个地方按下去，
    /// 两处之间的板面距离**不是**位移，必须把坐标基准清零重来。
    private var activeTouchID: Int?

    // 诊断
    public private(set) var estimatedSpeed: Double = 0      // 点/秒
    public private(set) var measuredReportInterval: TimeInterval = 0
    private var lastIngestTime: TimeInterval?

    public init() {}

    // MARK: - 输入

    /// 喂入一包解析结果。手指全部抬起时用空帧调用即可。
    public func ingest(_ frame: TouchpadFrame, arrivalTime: TimeInterval) {
        if let last = lastIngestTime {
            let interval = arrivalTime - last
            if interval > 0.001 && interval < 0.1 {
                // 指数滑动平均，用于自适应延迟与丢包判断
                if measuredReportInterval == 0 {
                    measuredReportInterval = interval
                } else {
                    measuredReportInterval = measuredReportInterval * 0.85 + interval * 0.15
                }
            }
        }
        lastIngestTime = arrivalTime

        guard !frame.samples.isEmpty else {
            // 手指离开触摸板 → 立刻结束追踪，并把采样队列与滤波基准一并丢弃。
            //
            // 这是「触摸板语义」的核心（2026-11-06 修正）：
            // 触摸板只输出**相对位移**，所以手指离开期间光标必须原地不动；
            // 手指在另一块区域重新按下时，两处之间的板面距离是「空间距离」而不是「位移」，
            // 绝不能换算成光标位移。
            //
            // 之前的实现只置 isTracking = false，把绝对坐标基准（filtered / lastEmitted）
            // 和历史采样留着，导致重新按下时「新位置 − 旧位置」被当成一两百点的位移甩出去，
            // 光标瞬移，接着的点击自然全部点偏。
            endTracking()
            return
        }

        // 单指时 frame.samples 已经是按时间排好序的完整序列（一包 3~4 个采样），
        // 每个采样的 slot 是「本包内第几个事件」，不代表不同手指 —— 全部消费。
        // 多指时 frame.samples 为空（解析器已置空），走不到这里。
        let primary = frame.samples.filter { $0.active }
        guard !primary.isEmpty else {
            endTracking()
            return
        }

        // 触点编号变了 = 旧手指已抬起、新手指已落下。
        // 蓝牙偶尔会漏发「无触摸帧」，靠这条兜底，避免一次漏包就把光标甩到别处。
        if let newID = primary.last?.touchID {
            if let oldID = activeTouchID, oldID != newID {
                softReset()
            }
            activeTouchID = newID
        }

        for s in primary {
            // 断触保护：极短时间内跨越大半个板宽，只可能是「抬手又落下」而非真实滑动。
            // 人手在 40ms 内最多移动约 0.12 个板宽，这里给 0.30 留足余量。
            // 命中后不丢弃该点，而是要重建基准 —— 丢弃会让手继续滑却毫无反应。
            if let prev = samples.last,
               s.time - prev.time < 0.040,
               hypot(s.x - prev.x, s.y - prev.y) > 0.30 {
                softReset()
            }
            samples.append(s)
        }

        // 裁剪历史
        let cutoff = arrivalTime - historyWindow
        if let firstKeep = samples.firstIndex(where: { $0.time >= cutoff }) {
            if firstKeep > 0 { samples.removeFirst(firstKeep) }
        } else if !samples.isEmpty {
            samples.removeAll()
        }

        isTracking = true
    }

    /// 结束一次触摸追踪：停止输出 + 丢弃所有绝对坐标基准。
    /// 下次按下时 `tick` 会走「第一帧建立基准、不产生位移」的分支，光标原地不动。
    private func endTracking() {
        isTracking = false
        activeTouchID = nil
        softReset()
    }

    /// 清空所有状态（停用/断开手柄时调用）
    public func reset() {
        samples.removeAll()
        filtered = nil
        lastEmitted = nil
        lastTickTime = nil
        lastTarget = nil
        lastTargetTime = nil
        lastIngestTime = nil
        estimatedSpeed = 0
        measuredReportInterval = 0
        isTracking = false
        activeTouchID = nil
    }

    /// 保留追踪状态但清掉滤波基准（用于重新按下时平滑接入）
    private func softReset() {
        filtered = nil
        lastEmitted = nil
        lastTickTime = nil
        lastTarget = nil
        lastTargetTime = nil
        samples.removeAll()
    }

    // MARK: - 输出

    /// 驱动一次输出。应由 240Hz 定时器调用。
    /// - Returns: 本 tick 的指针位移（像素点，单位为 macOS 逻辑点）
    public func tick(now: TimeInterval, screenSize: CGSize) -> CGVector {
        guard isTracking, !isFrozen else {
            lastTickTime = now
            return .zero
        }
        guard !samples.isEmpty else { return .zero }

        let queryTime = now - config.latency
        guard let target = interpolate(at: queryTime) else { return .zero }

        // 第一帧：建立基准，不产生位移
        guard var current = filtered, let base = lastEmitted else {
            filtered = target
            lastEmitted = target
            lastTickTime = now
            lastTarget = target
            lastTargetTime = now
            return .zero
        }

        let dt: TimeInterval
        if let last = lastTickTime {
            dt = min(max(now - last, 1.0 / 1000.0), 1.0 / 20.0)
        } else {
            dt = 1.0 / 240.0
        }
        lastTickTime = now

        // 目标移动速度（归一化 → 点/秒），用于自适应 τ 与增益
        let lagX = (target.x - current.x) * screenSize.width * config.sensitivity
        let lagY = (target.y - current.y) * screenSize.height * config.sensitivity
        let lagPoints = hypot(lagX, lagY)

        // 滞后量越大 → 手指动得越快 → τ 越小 → 越跟手
        let speedFactor = min(1.0, lagPoints / 22.0)
        let tau = 0.0035 + config.smoothing * 0.058 * (1.0 - 0.72 * speedFactor)
        let alpha = 1.0 - exp(-dt / max(tau, 0.0015))

        current.x += (target.x - current.x) * alpha
        current.y += (target.y - current.y) * alpha
        filtered = current

        // 差分 → 像素位移
        var dx = (current.x - base.x) * screenSize.width * config.sensitivity
        var dy = (current.y - base.y) * screenSize.height * config.sensitivity

        let distance = hypot(dx, dy)
        let speed = distance / dt
        estimatedSpeed = speed

        // 速度死区：静止时的坐标抖动直接吞掉（并把基准推到当前位置，防止累积后突然弹出）
        if speed < config.deadzoneSpeed {
            lastEmitted = current
            return .zero
        }

        // 低速精修：慢速时缩小增益，精细定位更可控
        if config.lowSpeedGain < 1.0 && speed < config.lowSpeedThreshold {
            let t = speed / max(config.lowSpeedThreshold, 1.0)
            let gain = config.lowSpeedGain + (1.0 - config.lowSpeedGain) * t
            dx *= gain
            dy *= gain
        }

        // 单 tick 上限，防坏包甩飞
        let capped = hypot(dx, dy)
        if capped > config.maxStepPerTick {
            let k = config.maxStepPerTick / capped
            dx *= k
            dy *= k
        }

        lastEmitted = current
        lastTarget = target
        lastTargetTime = now
        return CGVector(dx: dx, dy: dy)
    }

    // MARK: - 插值

    /// 在采样队列中按时间线性插值。
    /// 超出队列末端时钳制到末点（不外推，避免过冲抖动）。
    private func interpolate(at time: TimeInterval) -> CGPoint? {
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 {
            return CGPoint(x: samples[0].x, y: samples[0].y)
        }

        // 早于最早采样 → 用最早
        if time <= samples[0].time {
            return CGPoint(x: samples[0].x, y: samples[0].y)
        }
        // 晚于最新采样 → 用最新
        if time >= samples[samples.count - 1].time {
            let last = samples[samples.count - 1]
            return CGPoint(x: last.x, y: last.y)
        }

        // 二分找到区间
        var lo = 0
        var hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = samples[lo]
        let b = samples[hi]
        let span = b.time - a.time
        guard span > 0.0001 else { return CGPoint(x: b.x, y: b.y) }
        let t = (time - a.time) / span
        return CGPoint(x: a.x + (b.x - a.x) * t,
                       y: a.y + (b.y - a.y) * t)
    }
}
