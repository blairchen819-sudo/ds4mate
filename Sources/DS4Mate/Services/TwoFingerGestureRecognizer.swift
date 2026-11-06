// TwoFingerGestureRecognizer.swift
// 双指手势识别（纯逻辑，无 IO，可单测）
//
// 数据来源：DS4TouchParser 已按 touchID 分组好的「并行触点」。
// 实测确认固件支持双指（2026-11-06 抓包：单包内出现 2 个不同 touchID）。
//
// 两条独立通道：
//   1. 双指滚动 —— 两指**中点**的位移 → 滚轮像素
//   2. 捏合缩放 —— 两指**间距**的对数变化 → ⌘+ / ⌘-
//
// 为什么要用「对数」算缩放：
//   手指张开同样的物理距离，在间距小时感觉变化剧烈、间距大时感觉平缓。
//   用户的心理感知接近比例的等比变化，而不是线性的差值。
//   log(d_new / d_old) 正好把等比变化映射成等量增量，缩放手感才均匀。
//
// 为什么用「主导方向」而不是两条通道同时输出：
//   双指平移时两指间距必然有小幅波动，如果同时输出缩放，滚动会连带触发缩放，
//   在浏览器里表现为「滚着滚着页面字体变了」。所以每帧只走一条通道。

import Foundation
import CoreGraphics

// MARK: - 配置

public struct TwoFingerGestureConfig: Equatable {
    /// 是否启用双指手势
    public var isEnabled: Bool = true
    /// 滚动灵敏度：两指中点滑满整个触摸板高度 = 滚动多少像素
    public var scrollScale: Double = 2200.0
    /// 缩放灵敏度倍率（越大越敏感，需要的张开幅度越小）
    public var zoomScale: Double = 1.0
    /// 滚动方向反转（关闭系统「自然滚动」的用户需要打开）
    public var invertScroll: Bool = false

    public init() {}
}

// MARK: - 输出

public struct TwoFingerGestureOutput: Equatable {
    /// 水平滚动像素（正 = 向右）
    public var scrollX: Int32 = 0
    /// 垂直滚动像素（正 = 向上滚，符合 CGEvent 语义）
    public var scrollY: Int32 = 0
    /// 缩放档数：正 = 放大，负 = 缩小。每档对应一次 ⌘+ / ⌘-
    public var zoomSteps: Int = 0

    public var isScrolling: Bool { scrollX != 0 || scrollY != 0 }
    public var isZooming: Bool { zoomSteps != 0 }
    public var isActive: Bool { isScrolling || isZooming }

    public init(scrollX: Int32 = 0, scrollY: Int32 = 0, zoomSteps: Int = 0) {
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.zoomSteps = zoomSteps
    }
}

// MARK: - 识别器

public final class TwoFingerGestureRecognizer {

    public var config = TwoFingerGestureConfig()

    /// 触发一档缩放所需的累计对数变化量。
    /// 0.035 ≈ 两指间距变化 3.5%。取这个值是因为实测双指平移的间距抖动在 1~2%，
    /// 必须留出足够余量才不会误触发。
    private let zoomStepThreshold: Double = 0.035

    /// 最小滚动步长（像素）。pixel 单位下 1 像素的事件太密，会刷爆事件队列。
    private let minScrollStepPixels: Double = 2.0

    // 上一帧状态
    private var lastMid: CGPoint?
    private var lastDistance: Double?
    private var lastIDs: [Int] = []

    // 亚像素余量
    private var scrollAccX: Double = 0
    private var scrollAccY: Double = 0
    private var zoomAcc: Double = 0

    // 诊断
    public private(set) var gestureKind: String = "—"
    public private(set) var scrollPixelsTotal: Double = 0
    public private(set) var zoomStepsTotal: Int = 0

    public init() {}

    // MARK: - 输入

    /// 喂入一帧多指触点（长度 < 2 时自动复位并返回空输出）
    public func ingest(_ fingers: [FingerContact]) -> TwoFingerGestureOutput {
        guard config.isEnabled, fingers.count >= 2 else {
            reset()
            return TwoFingerGestureOutput()
        }

        // 只用前两根手指。三指及以上目前不参与，但也不会误触发。
        let a = fingers[0]
        let b = fingers[1]

        let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        let distance = hypot(a.x - b.x, a.y - b.y)
        let ids = [a.touchID, b.touchID]

        // 手指身份变了（换了一组手指按下）→ 重建基准，本帧不产生任何位移
        guard ids == lastIDs, let prevMid = lastMid, let prevDist = lastDistance else {
            lastIDs = ids
            lastMid = mid
            lastDistance = distance
            scrollAccX = 0
            scrollAccY = 0
            zoomAcc = 0
            gestureKind = "建立基准"
            return TwoFingerGestureOutput()
        }

        lastMid = mid
        lastDistance = distance

        // 中点位移（归一化）
        let dxN = mid.x - prevMid.x
        let dyN = mid.y - prevMid.y

        // 间距的对数变化
        let zoomDelta: Double = prevDist > 0.001
            ? log(max(distance, 0.001) / prevDist)
            : 0

        // 主导方向判定：间距变化占优 → 缩放；中点位移占优 → 滚动。
        // 位移量纲是「归一化坐标」，缩放量纲是「对数比例」，两者在双指手势里
        // 幅值范围接近（都是 0.001~0.1 量级），直接比较不需要额外换算。
        let dragMagnitude = abs(dxN) + abs(dyN)
        let isZoomDominant = abs(zoomDelta) > dragMagnitude

        var out = TwoFingerGestureOutput()

        if isZoomDominant {
            gestureKind = "捏合缩放"
            zoomAcc += zoomDelta
            let threshold = zoomStepThreshold / max(config.zoomScale, 0.1)
            while zoomAcc >= threshold {
                out.zoomSteps += 1
                zoomAcc -= threshold
            }
            while zoomAcc <= -threshold {
                out.zoomSteps -= 1
                zoomAcc += threshold
            }
            // 缩放期间不累加滚动，避免「捏合时页面跟着滚」
        } else {
            gestureKind = "双指滚动"
            scrollAccX += dxN
            scrollAccY += dyN

            let rawX = scrollAccX * config.scrollScale
            let rawY = scrollAccY * config.scrollScale

            if abs(rawX) >= minScrollStepPixels || abs(rawY) >= minScrollStepPixels {
                // 归一化 y 向下为正，而 CGEvent 的 wheel1 正值表示「向上滚」，
                // 两者方向相反 —— 但实测双指上滑（y 减小）应当看到下方内容，
                // 对应 wheel1 负值，所以这里**不取反**。
                let sx = rawX.rounded()
                let sy = rawY.rounded()
                let direction: Double = config.invertScroll ? -1.0 : 1.0
                out.scrollX = Int32(sx * direction)
                out.scrollY = Int32(sy * direction)
                // 只扣除已发出的整数部分，保留亚像素余量，避免慢速双指滑动丢位移
                scrollAccX -= (sx * direction) / config.scrollScale
                scrollAccY -= (sy * direction) / config.scrollScale
            }
        }

        if out.isScrolling { scrollPixelsTotal += hypot(Double(out.scrollX), Double(out.scrollY)) }
        if out.isZooming { zoomStepsTotal += abs(out.zoomSteps) }

        return out
    }

    /// 清空基准与累积量。单指接管或手指抬起时调用。
    public func reset() {
        lastMid = nil
        lastDistance = nil
        lastIDs = []
        scrollAccX = 0
        scrollAccY = 0
        zoomAcc = 0
        gestureKind = "—"
    }

    /// 诊断信息（设置页展示）
    public var diagnostics: String {
        String(format: "%@ · 滚动%.0fpx · 缩放%d档",
               gestureKind, scrollPixelsTotal, zoomStepsTotal)
    }
}
