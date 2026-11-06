// ControllerService.swift
// 内部用 IOHIDManager 直接读 PS4 HID 报告（绕开 macOS 26 上 GameController 框架的 PS4 事件 bug）
// 对外接口不变：activeProfile / isEnabled / connectionState / eventStream / lastInput

import Foundation
import CoreGraphics
import Combine
import AppKit
import IOBluetooth

public enum ControllerConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(controllerName: String)
}

public enum ControllerEvent {
    case buttonDown(ControllerInput)
    case buttonUp(ControllerInput)
    case axisChanged(ControllerInput, value: Double)
}

public final class ControllerService: ObservableObject {

    public static let shared = ControllerService()

    @Published public private(set) var connectionState: ControllerConnectionState = .disconnected
    @Published public private(set) var lastInput: (input: ControllerInput, at: Date)?
    @Published public var activeProfile: Profile?
    @Published public var isEnabled: Bool = true {
        didSet {
            // 停用映射时松开所有模拟中的修饰键，避免 Shift/Control 卡在按下状态
            if !isEnabled { eventSynthesizer.releaseAllModifiers() }
        }
    }
    /// 全局「切换预设」键：任何预设下按下它都会切到下一套。
    /// 与 Profile 内的 `.cycleProfile` 绑定并存，但优先级更高，换预设后依然有效。
    @Published public var profileSwitchInput: ControllerInput? = nil {
        didSet { persistProfileSwitchInput() }
    }
    /// 已收到的 HID 报告总数，用于界面自检
    @Published public private(set) var hidReportCount: Int = 0
    /// HID 层自检信息（未连接 / 权限不足 / 已连接）。
    /// 直接透传 HID 层的本地化结果：切语言时视图重算即可拿到新文案，
    /// 不需要等下一次状态变化。
    public var hidStatus: String { hidService.statusMessage }

    /// 触摸板诊断信息（设置页展示，用于排查「开关开了却没反应」）
    public var touchpadDiagnostics: String {
        let layoutText: String
        switch hidService.reportLayout {
        case .limited: layoutText = L("settings.touchpad.layout.limited")
        case .usbFull: layoutText = L("settings.touchpad.layout.usb")
        case .bluetoothFull: layoutText = L("settings.touchpad.layout.bluetooth")
        }
        return String(format: L("settings.touchpad.diagnostics"), layoutText, hidService.touchFrameCount)
    }

    private var lastLeftTrigger: Float = 0
    private var lastRightTrigger: Float = 0
    private var dragModeActive: Bool = false
    private var leftStickX: Double = 0
    private var leftStickY: Double = 0
    private var rightStickX: Double = 0
    private var rightStickY: Double = 0

    // MARK: - 平滑输出状态
    //
    // 蓝牙 PS4 的 HID 报文只有约 12Hz。如果每收到一帧就按帧位移，
    // 光标会一跳一跳（每帧 60+ 像素），既不平滑也不精确。
    // 这里把「摇杆 → 目标速度（像素/秒）」，由 60Hz 定时器做低通平滑后输出。

    /// 目标速度（px/s）
    private var cursorTargetX: Double = 0
    private var cursorTargetY: Double = 0
    /// 平滑后的当前速度（px/s）
    private var cursorCurrentX: Double = 0
    private var cursorCurrentY: Double = 0
    /// 左摇杆滚动通道
    private var scrollTargetX: Double = 0
    private var scrollTargetY: Double = 0
    private var scrollCurrentX: Double = 0
    private var scrollCurrentY: Double = 0
    /// 滚轮是整数事件，累积小数部分，避免低速时滚不动
    private var scrollRemainderX: Double = 0
    private var scrollRemainderY: Double = 0
    /// L2/R2 的阈值按下状态
    private var triggerPressedState: [ControllerInput: Bool] = [:]
    private let eventSynthesizer: EventSynthesizer
    private let hidService: HIDControllerService

    public let eventStream = PassthroughSubject<ControllerEvent, Never>()

    public init(eventSynthesizer: EventSynthesizer = .shared,
                hidService: HIDControllerService = .shared) {
        self.eventSynthesizer = eventSynthesizer
        self.hidService = hidService
        self.profileSwitchInput = Self.loadProfileSwitchInput()

        // 启动 HID 输入
        hidService.start(
            onButton: { [weak self] input, pressed in
                self?.handleButton(input, pressed: pressed)
            },
            onAxis: { [weak self] input, value in
                self?.handleAxis(input, value: value)
            },
            onTouch: { [weak self] frame in
                self?.handleTouch(frame)
            },
            onStats: { [weak self] count in
                DispatchQueue.main.async {
                    self?.hidReportCount = count
                }
            }
        )

        // 上次退出时若开着「触摸板当鼠标」，这里恢复运行
        if TouchpadMouseService.shared.isEnabled {
            TouchpadMouseService.shared.loadPersistedConfig()
            TouchpadMouseService.shared.start()
        }

        // 60Hz 平滑输出：HID 只有 ~12Hz，靠这个定时器把速度积分成平滑位移
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickMotion()
        }

        // 启动自检：确认 SkyLight 私有 API 可用、能读到桌面列表
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSLog("[DS4Mate/Space] available=%d desktops=%d",
                  SpaceSwitcher.shared.isAvailable ? 1 : 0,
                  SpaceSwitcher.shared.desktopCount)

            // 仅当环境变量 DS4_QWEN_PROBE=1 时探测一次千问的语音按钮，用于确认 AX 能否找到
            if ProcessInfo.processInfo.environment["DS4_QWEN_DUMP"] == "1" {
                QwenVoiceController.shared.dumpAllButtons()
            }
            if ProcessInfo.processInfo.environment["DS4_QWEN_PROBE"] == "1" {
                NSLog("[DS4Mate/Qwen] probe running=%d", QwenVoiceController.shared.isQwenRunning ? 1 : 0)
                let ok = QwenVoiceController.shared.toggleVoice()
                NSLog("[DS4Mate/Qwen] probe toggle -> %d", ok ? 1 : 0)
            }
        }

        // 监听 HID 服务的连接状态变化 + 自检信息
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let newState: ControllerConnectionState = self.hidService.isConnected
                ? .connected(controllerName: "DUALSHOCK 4")
                : .disconnected
            DispatchQueue.main.async {
                if newState != self.connectionState {
                    // 手柄断开时松开模拟中的修饰键，否则松开事件永远等不到
                    if case .connected = self.connectionState {
                        self.eventSynthesizer.releaseAllModifiers()
                        TouchpadMouseService.shared.engine.reset()
                    }
                    self.connectionState = newState
                }
            }
        }
    }

    // MARK: - 手柄唤醒 / 重连

    /// 主动唤醒已配对的 PS4 手柄：先发起蓝牙连接，再重新扫描 HID 设备。
    /// PS4 手柄休眠断开后只有按 PS 键才能被唤醒，用这里的 openConnection 可以省掉手动操作。
    public func reconnectController() {
        hidService.rescan()

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            NSLog("[DS4Mate] no paired bluetooth devices")
            return
        }
        var found = false
        for dev in paired {
            let name = dev.name ?? ""
            let upper = name.uppercased()
            guard upper.contains("DUALSHOCK") || upper.contains("WIRELESS CONTROLLER") else { continue }
            found = true
            if dev.isConnected() {
                NSLog("[DS4Mate] %@ already connected (BT), rescanning HID", name)
            } else {
                let r = dev.openConnection()
                NSLog("[DS4Mate] openConnection(%@) -> 0x%08X", name, UInt32(bitPattern: r))
            }
        }
        if !found {
            NSLog("[DS4Mate] no paired DualShock found — 需要先在系统蓝牙里配对手柄")
        }

        // 蓝牙栈建立连接需要时间，分几次重新扫描 HID
        for delay in [1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.hidService.rescan()
            }
        }
    }

    // MARK: - 按键处理

    // MARK: - 触摸板

    /// 收到一包触摸数据（含 prev / cur 两个子帧）。
    /// 只有「触摸板当鼠标」开启时才驱动指针；关闭时完全不影响原有映射。
    private func handleTouch(_ frame: TouchpadFrame) {
        guard isEnabled, TouchpadMouseService.shared.isEnabled else { return }
        TouchpadMouseService.shared.ingest(frame)
    }

    private func handleButton(_ input: ControllerInput, pressed: Bool) {
        NSLog("[DS4Mate] handleButton \(input.displayName) pressed=\(pressed) enabled=\(isEnabled) profile=\(activeProfile?.name ?? "nil")")
        DispatchQueue.main.async {
            self.lastInput = (input, Date())
        }
        guard isEnabled else { return }

        // 触摸板当鼠标模式：触摸板按下 = 鼠标左键，并且不再走原有映射
        // （否则会同时触发「调度中心」之类，变成一次点击两个动作）
        if input == .touchpadButton && TouchpadMouseService.shared.isEnabled {
            eventStream.send(pressed ? .buttonDown(input) : .buttonUp(input))
            TouchpadMouseService.shared.setPressed(pressed)
            eventSynthesizer.mouseButton(pressed ? .leftMouseDown : .leftMouseUp, button: .left)
            return
        }

        // 全局「切换预设」键优先于当前 Profile 的绑定：
        // 这样不论当前是哪套预设，按同一个键都能切到下一套。
        if let switchInput = profileSwitchInput, input == switchInput {
            eventStream.send(pressed ? .buttonDown(input) : .buttonUp(input))
            if pressed {
                NSLog("[DS4Mate] 全局切换键 \(input.displayName) → 下一个预设")
                NotificationCenter.default.post(name: .ds4mateCycleProfile, object: nil)
            }
            return
        }

        guard let profile = activeProfile,
              let binding = profile.binding(for: input) else {
            return
        }
        NSLog("[DS4Mate]   binding.action = \(binding.action.displayName)")
        if case .mouseDragToggle = binding.action, pressed {
            dragModeActive.toggle()
            return
        }
        // 按住型修饰键：按下置位、松开清除，两个方向都要处理
        if case .holdModifier(let key) = binding.action {
            eventSynthesizer.setModifier(key, pressed: pressed)
            eventStream.send(pressed ? .buttonDown(input) : .buttonUp(input))
            return
        }
        if pressed {
            eventStream.send(.buttonDown(input))
            executeAction(binding.action)
        } else {
            eventStream.send(.buttonUp(input))
        }
    }

    private func handleAxis(_ input: ControllerInput, value: Double) {
        // 摇杆：累积后合并触发 handleStick
        switch input {
        case .leftStickX: leftStickX = value
        case .leftStickY: leftStickY = value
        case .rightStickX: rightStickX = value
        case .rightStickY: rightStickY = value
        default:
            break
        }
        if input == .leftStickX || input == .leftStickY {
            handleStick(left: true, x: leftStickX, y: leftStickY)
        } else if input == .rightStickX || input == .rightStickY {
            handleStick(left: false, x: rightStickX, y: rightStickY)
        } else {
            // 扳机走原来的 handleAnalogAxis
            handleAnalogAxis(input, value: value)
        }
    }

    private func handleAnalogAxis(_ input: ControllerInput, value: Double) {
        guard isEnabled,
              let profile = activeProfile,
              let binding = profile.binding(for: input) else {
            triggerPressedState[input] = false
            return
        }

        eventStream.send(.axisChanged(input, value: value))

        // 扳机是 0...1 的单调值，没有「按下瞬间」，只能靠阈值模拟按键。
        // 之前的实现只处理了 fineScroll，其余动作全部 break —— 这就是
        // 「L2/R2 绑键位不生效」的根因。
        let threshold = max(profile.parameters.triggerThreshold, 0.05)
        let nowPressed = value >= threshold
        let wasPressed = triggerPressedState[input] ?? false

        if nowPressed != wasPressed {
            triggerPressedState[input] = nowPressed
            if nowPressed {
                DispatchQueue.main.async { self.lastInput = (input, Date()) }
                NSLog("[DS4Mate] trigger \(input.displayName) 按下 value=\(String(format: "%.2f", value))")
                if case .fineScroll = binding.action {
                    // 精细滚动是持续动作，由下面的模拟量分支处理
                } else {
                    executeAction(binding.action)
                }
            } else {
                NSLog("[DS4Mate] trigger \(input.displayName) 松开")
            }
        }

        // 精细滚动：按深度映射速度
        if case .fineScroll = binding.action {
            let dz = max(profile.parameters.deadzone, 0.02)
            guard value > dz else { return }
            let n = (value - dz) / (1 - dz)
            let delta = pow(n, 1.5) * 8.0 * profile.parameters.fineScrollSensitivity
            eventSynthesizer.scroll(dy: Int32(input == .rightTriggerAxis ? delta : -delta))
        }
    }

    private func handleStick(left: Bool, x: Double, y: Double) {
        guard isEnabled, let profile = activeProfile else {
            // 未启用 / 无预设：把速度清零，避免光标一直飘
            if left {
                scrollTargetX = 0; scrollTargetY = 0
            } else {
                cursorTargetX = 0; cursorTargetY = 0
            }
            return
        }

        let deadzone = profile.parameters.deadzone
        let inputX: ControllerInput = left ? .leftStickX : .rightStickX
        let inputY: ControllerInput = left ? .leftStickY : .rightStickY

        eventStream.send(.axisChanged(inputX, value: abs(x) < deadzone ? 0 : x))
        eventStream.send(.axisChanged(inputY, value: abs(y) < deadzone ? 0 : y))

        let bindingX = profile.binding(for: inputX)
        let bindingY = profile.binding(for: inputY)

        // 死区外重新归一化，再套幂曲线：小幅慢（好瞄准）、大幅快
        let sx = shapeStick(x, deadzone: deadzone)
        let sy = shapeStick(y, deadzone: deadzone)

        if left {
            let sens = 1400.0 * profile.parameters.scrollSensitivity
            scrollTargetX = isScrollBinding(bindingX) ? sx * sens : 0
            scrollTargetY = isScrollBinding(bindingY) ? sy * sens : 0
        } else {
            // 关键：X 和 Y 合成一个速度向量，由 tickMotion 一次性位移。
            // 旧实现分两次 moveCursor，每次都读系统光标位置，
            // 第二次读到的是旧位置，把 X 位移覆盖掉了 —— 所以只有上下能动。
            let sens = 1900.0 * profile.parameters.cursorSensitivity
            let invX = profile.parameters.invertRightStickX ? -1.0 : 1.0
            let invY = profile.parameters.invertRightStickY ? -1.0 : 1.0
            // 方向约定：
            //   HID 原始值 X: 0=左 255=右，Y: 0=上 255=下（HID Usage Tables 规定 Y 向下为正）
            //   shapeStick 后 X: 左负右正，Y: 上负下正 —— 与 CGEvent 屏幕坐标完全一致
            //   所以两轴都直通，不能再对 Y 取反，否则上下/斜向会镜像
            cursorTargetX = isMoveCursorBinding(bindingX) ? sx * sens * invX : 0
            cursorTargetY = isMoveCursorBinding(bindingY) ? sy * sens * invY : 0
        }
    }

    /// 死区内输出 0；死区外把 [deadzone, 1] 拉伸回 [0, 1]，再取幂
    private func shapeStick(_ value: Double, deadzone: Double) -> Double {
        let a = abs(value)
        guard a > deadzone else { return 0 }
        let span = max(1.0 - deadzone, 0.001)
        let n = min((a - deadzone) / span, 1.0)
        let shaped = pow(n, 1.7)
        return value < 0 ? -shaped : shaped
    }

    private func isMoveCursorBinding(_ binding: KeyBinding?) -> Bool {
        if case .mouseMoveCursor? = binding?.action { return true }
        return false
    }

    private func isScrollBinding(_ binding: KeyBinding?) -> Bool {
        if case .scroll? = binding?.action { return true }
        return false
    }

    // MARK: - 60Hz 平滑输出

    private func tickMotion() {
        guard isEnabled else {
            cursorTargetX = 0; cursorTargetY = 0
            cursorCurrentX = 0; cursorCurrentY = 0
            scrollTargetX = 0; scrollTargetY = 0
            scrollCurrentX = 0; scrollCurrentY = 0
            return
        }

        let dt = 1.0 / 60.0
        let alpha = 0.22   // 一阶低通，约 8 帧收敛：不拖沓也不生硬

        cursorCurrentX += (cursorTargetX - cursorCurrentX) * alpha
        cursorCurrentY += (cursorTargetY - cursorCurrentY) * alpha

        if abs(cursorCurrentX) > 0.2 || abs(cursorCurrentY) > 0.2 {
            eventSynthesizer.moveCursor(dx: cursorCurrentX * dt, dy: cursorCurrentY * dt)
        } else if cursorCurrentX != 0 || cursorCurrentY != 0 {
            cursorCurrentX = 0
            cursorCurrentY = 0
        }

        scrollCurrentX += (scrollTargetX - scrollCurrentX) * alpha
        scrollCurrentY += (scrollTargetY - scrollCurrentY) * alpha
        scrollRemainderX += scrollCurrentX * dt
        scrollRemainderY += scrollCurrentY * dt

        let ix = Int32(scrollRemainderX.rounded(.towardZero))
        let iy = Int32(scrollRemainderY.rounded(.towardZero))
        if ix != 0 || iy != 0 {
            scrollRemainderX -= Double(ix)
            scrollRemainderY -= Double(iy)
            eventSynthesizer.scroll(dx: ix, dy: iy)
        }
        if abs(scrollCurrentX) < 0.5 && abs(scrollCurrentY) < 0.5 {
            scrollCurrentX = 0
            scrollCurrentY = 0
            scrollRemainderX = 0
            scrollRemainderY = 0
        }
    }

    // MARK: - 全局切换键持久化

    private static let profileSwitchInputKey = "ds4mate.profileSwitchInput"

    private static func loadProfileSwitchInput() -> ControllerInput? {
        guard let raw = UserDefaults.standard.string(forKey: profileSwitchInputKey) else {
            return nil
        }
        return ControllerInput(rawValue: raw)
    }

    private func persistProfileSwitchInput() {
        if let input = profileSwitchInput {
            UserDefaults.standard.set(input.rawValue, forKey: Self.profileSwitchInputKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.profileSwitchInputKey)
        }
    }

    // MARK: - 动作执行

    private func executeAction(_ action: Action) {
        switch action {
        case .none: break
        case .mouseLeftClick:
            eventSynthesizer.click(type: .leftMouseDown)
        case .mouseRightClick:
            eventSynthesizer.click(type: .rightMouseDown)
        case .mouseMiddleClick:
            eventSynthesizer.middleClick()
        case .mouseDoubleClick:
            eventSynthesizer.doubleClick()
        case .mouseDragToggle: break
        case .mouseMoveCursor, .scroll, .fineScroll: break
        case .holdModifier: break   // 在 handleButton 里双向处理，这里不重复触发
        case .keyPress(let code, let mods):
            eventSynthesizer.keyPress(keyCode: code, modifiers: mods)
        case .keyChord(let codes, let mods):
            eventSynthesizer.keyChord(keyCodes: codes, modifiers: mods)
        case .systemShortcut(let s):
            eventSynthesizer.systemShortcut(s)
        case .mediaKey(let m):
            eventSynthesizer.mediaKey(m)
        case .exitApp:
            eventSynthesizer.releaseAllModifiers()
            NSApp.terminate(nil)
        case .toggleAppEnabled:
            isEnabled.toggle()
        case .cycleProfile:
            NotificationCenter.default.post(name: .ds4mateCycleProfile, object: nil)
        case .openMainWindow:
            NotificationCenter.default.post(name: .ds4mateOpenMainWindow, object: nil)
        case .toggleQwenVoice:
            QwenVoiceController.shared.toggleVoice()
        case .toggleQwenMic:
            QwenVoiceController.shared.toggleMicrophone()
        case .iflytekVoice:
            IFlytekVoiceController.shared.toggle()
        }
    }
}

public extension Notification.Name {
    static let ds4mateCycleProfile = Notification.Name("ds4mate.cycleProfile")
    static let ds4mateOpenMainWindow = Notification.Name("ds4mate.openMainWindow")
}
