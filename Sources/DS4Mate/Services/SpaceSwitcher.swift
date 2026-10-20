import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// 桌面（Spaces）切换。
///
/// 这条路是逐个试出来的，**别再回头试那几种**：
///
/// 无效（都实测过，且用「标记窗口」验证过真假）：
/// - `CGEvent` 合成 ⌃← / ⌃→（含完整 flagsChanged 序列）—— WindowServer 不认合成事件
/// - `CGEvent.postToPid`
/// - 合成三指滑动（带 scrollPhase 的连续 scroll 事件）
/// - 虚拟 HID 键盘 `IOHIDUserDeviceCreate` —— macOS 26 上创建失败
/// - `CGSManagedDisplaySetCurrentSpace` / `SLSManagedDisplaySetCurrentSpace`
///   —— **两个都只改系统记录，画面纹丝不动**。
///   验证方法：在一个桌面里开一个窗口当标记，切走后再查窗口列表，标记窗口还在 → 没切。
///   更坑的是它会把「记录」和「画面」搞得不一致，之后所有判断都失真。
///
/// 有效：
/// - 打开调度中心，里面每个桌面都是一个 `AXButton`（标题「桌面1」「桌面2」…），
///   `AXPress` 它 = 系统自己的切桌面动作。实测按压后标记窗口消失、画面差异 76%。
///
/// 代价：按压时调度中心会闪一下（窗口缩略图铺开再收回），整个过程约 1.5~2 秒。
public final class SpaceSwitcher {

    public static let shared = SpaceSwitcher()

    private typealias CGSConnectionID = UInt32
    private typealias MainConnectionFn = @convention(c) () -> CGSConnectionID
    private typealias CopyDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?

    private var mainConnection: MainConnectionFn?
    /// 只读：拿当前 space、桌面数量。**绝不调用任何 Set 接口**。
    private var copyDisplaySpaces: CopyDisplaySpacesFn?

    public private(set) var isAvailable = false

    private static let missionControlPath = "/System/Applications/Mission Control.app"

    private struct SpaceInfo {
        let displayID: String
        let current: UInt64
        let spaces: [(id: UInt64, type: Int)]

        /// type 0 = 普通桌面；type 4 = 全屏应用占用的 space，不参与循环
        var desktops: [UInt64] { spaces.filter { $0.type == 0 }.map { $0.id } }
    }

    private init() {
        load()
    }

    private func load() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            NSLog("[DS4Mate/Space] SkyLight 加载失败")
            return
        }
        guard let m = dlsym(handle, "CGSMainConnectionID"),
              let c = dlsym(handle, "CGSCopyManagedDisplaySpaces") else {
            NSLog("[DS4Mate/Space] SkyLight 符号缺失")
            return
        }
        mainConnection = unsafeBitCast(m, to: MainConnectionFn.self)
        copyDisplaySpaces = unsafeBitCast(c, to: CopyDisplaySpacesFn.self)
        isAvailable = true
        NSLog("[DS4Mate/Space] SpaceSwitcher 就绪（调度中心方案）")
    }

    private func snapshot() -> SpaceInfo? {
        guard let cid = mainConnection?(),
              let arr = copyDisplaySpaces?(cid)?.takeRetainedValue() as? [[String: Any]],
              let main = arr.first,
              let spaces = main["Spaces"] as? [[String: Any]],
              let cur = main["Current Space"] as? [String: Any] else {
            return nil
        }
        return SpaceInfo(
            displayID: main["Display Identifier"] as? String ?? "Main",
            current: cur["ManagedSpaceID"] as? UInt64 ?? 0,
            spaces: spaces.map {
                (id: $0["ManagedSpaceID"] as? UInt64 ?? 0,
                 type: $0["type"] as? Int ?? 0)
            }
        )
    }

    /// 当前主显示器上的虚拟桌面数量（不含全屏 space）
    public var desktopCount: Int {
        snapshot()?.desktops.count ?? 0
    }

    /// 当前所在 space 的 ID，用于「切走再切回」
    public var currentSpaceID: UInt64? {
        snapshot()?.current
    }

    /// 切换动画期间忽略连按，否则会连开好几次调度中心
    private var isSwitching = false

    /// 在虚拟桌面之间循环切换。
    /// - Parameter direction: +1 下一个，-1 上一个
    @discardableResult
    public func switchDesktop(_ direction: Int) -> Bool {
        guard isAvailable, let info = snapshot() else { return false }
        guard !isSwitching else {
            NSLog("[DS4Mate/Space] 上一次切换还没结束，忽略")
            return false
        }
        let desktops = info.desktops
        guard desktops.count > 1 else {
            NSLog("[DS4Mate/Space] 只有 \(desktops.count) 个虚拟桌面，无需切换")
            return false
        }
        let target: Int
        if let cur = desktops.firstIndex(of: info.current) {
            target = ((cur + direction) % desktops.count + desktops.count) % desktops.count
            NSLog("[DS4Mate/Space] 请求切换：桌面 %d → %d（共 %d 个）",
                  cur + 1, target + 1, desktops.count)
        } else if let curIdx = info.spaces.firstIndex(where: { $0.id == info.current }) {
            // 当前在全屏应用占的 space 里（type=4），它没有缩略图、本身不参与循环。
            // 按 space 在系统里的真实排列，朝目标方向找最近的普通桌面。
            let n = info.spaces.count
            var found: UInt64?
            for step in 1...n {
                let i = ((curIdx + direction * step) % n + n) % n
                if info.spaces[i].type == 0 { found = info.spaces[i].id; break }
            }
            guard let hit = found, let idx = desktops.firstIndex(of: hit) else {
                NSLog("[DS4Mate/Space] 全屏 space 旁边没有普通桌面，放弃")
                return false
            }
            target = idx
            NSLog("[DS4Mate/Space] 当前在全屏 space，切到桌面 %d（共 %d 个）", idx + 1, desktops.count)
        } else {
            NSLog("[DS4Mate/Space] 当前 space %lld 找不到位置，放弃", info.current)
            return false
        }
        return pressThumbnail(desktopNumber: target + 1, expectedSpace: desktops[target])
    }

    /// 切到指定 space。用于操作完别的应用后切回原桌面。
    /// 只支持普通桌面；全屏 space 没有缩略图，做不到。
    @discardableResult
    public func switchToSpace(_ id: UInt64) -> Bool {
        guard isAvailable, let info = snapshot() else { return false }
        guard id != info.current else { return true }
        let desktops = info.desktops
        guard let idx = desktops.firstIndex(of: id) else {
            NSLog("[DS4Mate/Space] %lld 不是普通桌面（可能是全屏 space），无法直达", id)
            return false
        }
        return pressThumbnail(desktopNumber: idx + 1, expectedSpace: id)
    }

    // MARK: - 调度中心

    private func pressThumbnail(desktopNumber: Int, expectedSpace: UInt64) -> Bool {
        guard !isSwitching else { return false }
        isSwitching = true

        openMissionControl()
        pollThumbnail(desktopNumber: desktopNumber, expectedSpace: expectedSpace, attempt: 1)
        return true
    }

    private func openMissionControl() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", Self.missionControlPath]
        do {
            try task.run()
        } catch {
            NSLog("[DS4Mate/Space] 打开调度中心失败: %@", error.localizedDescription)
        }
    }

    /// 调度中心展开有动画，缩略图元素要等它建出来，所以轮询而不是死等固定时间。
    private func pollThumbnail(desktopNumber: Int, expectedSpace: UInt64, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 1 ? 0.9 : 0.18)) { [weak self] in
            guard let self = self else { return }
            let buttons = self.desktopButtons()
            if let hit = buttons.first(where: { $0.number == desktopNumber }) {
                // 用 AXPress（系统自己的动作），不要用鼠标点：坐标会随桌面数量漂移
                let r = AXUIElementPerformAction(hit.element, kAXPressAction as CFString)
                NSLog("[DS4Mate/Space] 按下「%@」-> %d（第 %d 次尝试）", hit.title, Int(r.rawValue), attempt)
                self.verify(expectedSpace: expectedSpace)
                return
            }
            if attempt < 14 {
                self.pollThumbnail(desktopNumber: desktopNumber, expectedSpace: expectedSpace, attempt: attempt + 1)
            } else {
                NSLog("[DS4Mate/Space] 调度中心里没有「桌面%d」（找到 %@），取消",
                      desktopNumber, buttons.map { $0.title })
                self.dismissMissionControl()
                self.isSwitching = false
            }
        }
    }

    private func verify(expectedSpace: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            let now = self.snapshot()?.current ?? 0
            NSLog("[DS4Mate/Space] verify current=%lld expected=%lld -> %@",
                  now, expectedSpace, now == expectedSpace ? "OK" : "FAILED")
            self.isSwitching = false
        }
    }

    /// 失败时把调度中心收掉，别把用户丢在那儿
    private func dismissMissionControl() {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
        NSLog("[DS4Mate/Space] 已发 Esc 收起调度中心")
    }

    // MARK: - 读取调度中心的桌面缩略图

    private struct DesktopButton {
        let number: Int
        let title: String
        let element: AXUIElement
    }

    /// 桌面缩略图挂在 Dock 进程的 AX 树上（调度中心不是独立进程）。
    /// 中文系统标题是「桌面1」，英文是「Desktop 1」，两种都认。
    private func desktopButtons() -> [DesktopButton] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return []
        }
        let ax = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1.5)

        var out: [DesktopButton] = []
        var visited = 0
        collectDesktopButtons(ax, depth: 0, visited: &visited, into: &out)
        return out.sorted { $0.number < $1.number }
    }

    private func collectDesktopButtons(_ element: AXUIElement, depth: Int,
                                       visited: inout Int, into out: inout [DesktopButton]) {
        guard depth < 14, visited < 6000 else { return }
        visited += 1

        let role = (attribute(element, kAXRoleAttribute) as? String) ?? ""
        if role == "AXButton" {
            let title = (attribute(element, kAXTitleAttribute) as? String) ?? ""
            if let n = Self.desktopNumber(in: title) {
                out.append(DesktopButton(number: n, title: title, element: element))
            }
        }

        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children {
            collectDesktopButtons(child, depth: depth + 1, visited: &visited, into: &out)
        }
    }

    private static func desktopNumber(in title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        for prefix in ["桌面", "Desktop", "desktop"] where trimmed.hasPrefix(prefix) {
            let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let n = Int(rest), n > 0 { return n }
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
