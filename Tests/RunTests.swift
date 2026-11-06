// DS4Mate 自带冒烟测试
// 用法：build/DS4MateTests
// 不依赖 XCTest/Testing 框架，在没 Xcode 的环境也能跑

import Foundation
import CoreGraphics

@main
struct DS4MateTestRunner {
    static func main() {
        // 简化的断言工具
        var passed = 0
        var failed = 0
        var currentSuite = ""

        func suite(_ name: String, _ block: () throws -> Void) {
            currentSuite = name
            print("\n=== \(name) ===")
            do {
                try block()
            } catch {
                print("  SUITE FAILED: \(error)")
                failed += 1
            }
        }

        func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
            if condition {
                print("  ✓ \(message)")
                passed += 1
            } else {
                print("  ✗ \(message) [\(file.split(separator: "/").last ?? ""):\(line)]")
                failed += 1
            }
        }

        func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
            if a == b {
                print("  ✓ \(message)")
                passed += 1
            } else {
                print("  ✗ \(message): 期望 \(b), 实际 \(a) [\(file.split(separator: "/").last ?? ""):\(line)]")
                failed += 1
            }
        }

        func expectThrows(_ block: () throws -> Void, _ message: String) {
            do {
                try block()
                print("  ✗ \(message) (应该抛错但没抛)")
                failed += 1
            } catch {
                print("  ✓ \(message)")
                passed += 1
            }
        }

        print("DS4Mate 冒烟测试")
        print("=================")
        print("运行时间：\(Date())")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // =====================================================
        // Suite 1: ControllerInput
        // =====================================================
        suite("ControllerInput") {
            expectEqual(ControllerInput.allCases.count, 22, "Input 总数 22（Spec §6.1）")

            let all = ControllerInput.allCases
            let unique = Set(all)
            expect(all.count == unique.count, "所有 input 唯一")

            expect(ControllerInput.leftStickX.isAnalog, "左摇杆 X 是模拟轴")
            expect(ControllerInput.leftStickY.isAnalog, "左摇杆 Y 是模拟轴")
            expect(ControllerInput.rightStickX.isAnalog, "右摇杆 X 是模拟轴")
            expect(ControllerInput.rightTriggerAxis.isAnalog, "R2 是模拟轴")
            expect(!ControllerInput.cross.isAnalog, "× 键不是模拟轴")
            expect(!ControllerInput.ps.isAnalog, "PS 键不是模拟轴")

            for input in ControllerInput.allCases {
                expect(!input.displayName.isEmpty, "\(input.rawValue) 有 displayName")
            }
        }

        // =====================================================
        // Suite 2: Action
        // =====================================================
        suite("Action") {
            // Codable round-trip
            do {
                let original = Action.keyChord(keyCodes: [8, 9], modifiers: [.maskCommand, .maskShift])
                let encoded = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(Action.self, from: encoded)
                expectEqual(decoded, original, "keyChord Codable round-trip")
            } catch {
                print("  ✗ keyChord Codable 编码失败：\(error)")
                failed += 1
            }

            do {
                let original = Action.systemShortcut(.screenshotSelection)
                let encoded = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(Action.self, from: encoded)
                expectEqual(decoded, original, "systemShortcut Codable round-trip")
            } catch {
                print("  ✗ systemShortcut Codable 失败：\(error)")
                failed += 1
            }

            do {
                let original = Action.mediaKey(.playPause)
                let encoded = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(Action.self, from: encoded)
                expectEqual(decoded, original, "mediaKey Codable round-trip")
            } catch {
                print("  ✗ mediaKey Codable 失败：\(error)")
                failed += 1
            }

            // 非法类型抛错
            expectThrows({
                let json = "{\"type\":\"invalidType\"}".data(using: .utf8)!
                _ = try JSONDecoder().decode(Action.self, from: json)
            }, "非法 Action type 抛错")

            // 分类
            expectEqual(Action.mouseLeftClick.category, .mouse, "mouseLeftClick 分类为 mouse")
            expectEqual(Action.keyPress(keyCode: 0, modifiers: []).category, .keyboard, "keyPress 分类为 keyboard")
            expectEqual(Action.systemShortcut(.showDesktop).category, .system, "systemShortcut 分类为 system")
            expectEqual(Action.mediaKey(.playPause).category, .media, "mediaKey 分类为 media")
            expectEqual(Action.none.category, .meta, "none 分类为 meta")
            expectEqual(Action.exitApp.category, .meta, "exitApp 分类为 meta")

            // SystemShortcut 文案
            expectEqual(SystemShortcut.showDesktop.keyCombo, "F11", "showDesktop 快捷键 F11")
            expectEqual(SystemShortcut.screenshotSelection.keyCombo, "⌘⇧4", "screenshotSelection ⌘⇧4")
            expectEqual(SystemShortcut.lockScreen.keyCombo, "⌘⌃Q", "lockScreen ⌘⌃Q")
        }

        // =====================================================
        // Suite 3: 初始预设
        // =====================================================
        suite("初始预设") {
            let starter = ProfileStore.makeStarterProfile()
            expectEqual(starter.name, L("profile.starter"), "初始预设名称跟随界面语言")
            expect(!starter.isBuiltin, "初始预设是普通预设（非内置）")
            for input in ControllerInput.allCases {
                expect(starter.binding(for: input) != nil, "初始预设覆盖 \(input.displayName)")
            }

            // PS 键默认禁用（避免误触）
            if let binding = starter.binding(for: .ps) {
                if case .none = binding.action {
                    expect(true, "初始预设 PS 键禁用")
                } else {
                    print("  ✗ 初始预设 PS 键应禁用，实际：\(binding.action)")
                    failed += 1
                }
            }

            // Options 键 = exitApp
            if let binding = starter.binding(for: .options) {
                if case .exitApp = binding.action {
                    expect(true, "初始预设 Options 键 = exitApp")
                } else {
                    print("  ✗ 初始预设 Options 键应 exitApp，实际：\(binding.action)")
                    failed += 1
                }
            }
        }

        // =====================================================
        // Suite 4: ProfileStore（临时目录，不碰用户真实预设）
        // =====================================================
        suite("ProfileStore") {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("DS4MateTests-\(UUID().uuidString)", isDirectory: true)
            let store = ProfileStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // 空目录 → 自动补一份初始预设，列表不会是空的
            let initial = store.loadAll()
            expectEqual(initial.count, 1, "空目录自动生成一份初始预设")
            expectEqual(initial.first?.name, L("profile.starter"), "初始预设名称跟随界面语言")

            // 再加载一次不会重复生成
            expectEqual(store.loadAll().count, 1, "初始预设不会重复生成")

            // 保存并加载自定义预设
            let testID = UUID()
            let custom = Profile(
                id: testID,
                name: "测试-\(testID.uuidString.prefix(8))",
                isBuiltin: false,
                bindings: [KeyBinding(input: .cross, action: .exitApp)],
                parameters: .defaults
            )
            do {
                try store.save(custom)
                let reloaded = store.loadAll()
                let found = reloaded.first(where: { $0.id == testID })
                expect(found != nil, "保存的预设重新加载成功")
                if let found = found {
                    expectEqual(found.name, custom.name, "预设名称一致")
                    expectEqual(found.bindings.count, 1, "预设绑定数 1")
                }
                try? store.delete(custom)
                expectEqual(store.loadAll().count, 1, "删除后只剩初始预设")

                // 重复删除应当幂等（文件已经不在了）
                do {
                    try store.delete(custom)
                    expect(true, "重复删除不报错（幂等）")
                } catch {
                    print("  ✗ 重复删除报错：\(error)")
                    failed += 1
                }
            } catch {
                print("  ✗ 保存/加载失败：\(error)")
                failed += 1
            }

            // isBuiltin 作为历史数据兼容字段保留，仍然拒绝落盘
            expectThrows({
                try store.save(Profile(name: "非法内置", isBuiltin: true))
            }, "不能保存内置标记的 Profile")
        }

        // =====================================================
        // Suite 4b: ProfileStore.saveAs
        // =====================================================
        suite("ProfileStore.saveAs") {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("DS4MateTests-\(UUID().uuidString)", isDirectory: true)
            let store = ProfileStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let source = ProfileStore.makeStarterProfile()
            let name = "另存测试-\(UUID().uuidString.prefix(8))"
            do {
                let copy = try store.saveAs(source, name: name)
                expectEqual(copy.name, name, "另存为名称正确")
                expect(!copy.isBuiltin, "另存为得到普通预设")
                expect(copy.id != source.id, "另存为生成新 ID")
                expectEqual(copy.bindings.count, source.bindings.count, "另存为绑定数一致")
                let reloaded = store.loadAll()
                expect(reloaded.contains(where: { $0.id == copy.id }), "另存为落盘后可重新加载")
                try? store.delete(copy)
            } catch {
                print("  ✗ saveAs 失败：\(error)")
                failed += 1
            }
        }

        // =====================================================
        // Suite: 本地化 · 语言解析
        // =====================================================
        suite("本地化 · 语言解析") {
            expectEqual(Localization.parse("en"), .english, "en → 英文")
            expectEqual(Localization.parse("en-US"), .english, "en-US → 英文")
            expectEqual(Localization.parse("zh"), .chinese, "zh → 中文")
            expectEqual(Localization.parse("zh-Hans"), .chinese, "zh-Hans → 中文")
            expectEqual(Localization.parse("zh_CN"), .chinese, "zh_CN → 中文")
            expect(Localization.parse("fr") == nil, "未知语言返回 nil")

            expectEqual(Localization.systemPreferredLanguage(preferredLanguages: ["zh-Hans-CN"]), .chinese,
                        "系统首选中文")
            expectEqual(Localization.systemPreferredLanguage(preferredLanguages: ["en-US"]), .english,
                        "系统首选英文")
            expectEqual(Localization.systemPreferredLanguage(preferredLanguages: []), .english,
                        "系统无首选语言时兜底英文")

            let defaults = UserDefaults(suiteName: "ds4mate.tests.lang")!
            defaults.removePersistentDomain(forName: "ds4mate.tests.lang")
            expectEqual(Localization.resolveInitialLanguage(defaults: defaults, environment: [:]),
                        Localization.systemPreferredLanguage(),
                        "没有偏好时跟随系统语言")
            expectEqual(Localization.resolveInitialLanguage(
                defaults: defaults, environment: [Localization.environmentKey: "zh"]), .chinese,
                        "环境变量覆盖优先")
            defaults.set("en", forKey: Localization.userDefaultsKey)
            expectEqual(Localization.resolveInitialLanguage(defaults: defaults, environment: [:]),
                        .english, "持久化偏好生效")
            expect(defaults.string(forKey: Localization.userDefaultsKey) == "en",
                   "运行期不覆写偏好")
            defaults.removePersistentDomain(forName: "ds4mate.tests.lang")
        }

        // =====================================================
        // Suite: 本地化 · 词条表
        // =====================================================
        suite("本地化 · 词条表") {
            let en = L10nTable.en
            let zh = L10nTable.zh

            expectEqual(en.count, zh.count, "中英词条数量一致（\(en.count)）")

            let onlyEN = Set(en.keys).subtracting(zh.keys).sorted()
            let onlyZH = Set(zh.keys).subtracting(en.keys).sorted()
            expect(onlyEN.isEmpty, "没有只在英文表里的 key\(onlyEN.isEmpty ? "" : "：\(onlyEN.prefix(5))")")
            expect(onlyZH.isEmpty, "没有只在中文表里的 key\(onlyZH.isEmpty ? "" : "：\(onlyZH.prefix(5))")")

            let emptyValues = en.filter { $0.value.isEmpty }.keys.sorted()
                + zh.filter { $0.value.isEmpty }.keys.sorted()
            expect(emptyValues.isEmpty, "没有空词条\(emptyValues.isEmpty ? "" : "：\(emptyValues.prefix(5))")")

            // 占位符必须两边一致，否则格式化会少填或多填参数
            func placeholders(_ text: String) -> [String] {
                let pattern = "%[-0-9.]*[@a-zA-Z]"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
                let range = NSRange(text.startIndex..., in: text)
                return regex.matches(in: text, range: range).compactMap {
                    Range($0.range, in: text).map { String(text[$0]) }
                }
            }
            let mismatched = Set(en.keys).intersection(zh.keys).filter {
                placeholders(en[$0] ?? "") != placeholders(zh[$0] ?? "")
            }.sorted()
            expect(mismatched.isEmpty,
                   "中英占位符一致\(mismatched.isEmpty ? "" : "：\(mismatched.prefix(5))")")

            // 切换语言后取值与格式化都要跟着变
            let original = Localization.shared.language
            defer { Localization.shared.setLanguage(original) }

            Localization.shared.setLanguage(.chinese)
            expectEqual(L("profile.starter"), "默认", "中文：初始预设名")
            expectEqual(L("editor.reset.confirm", 3), "删除 3 份预设", "中文：带参数词条")
            expectEqual(ProfileStore.makeStarterProfile().name, "默认", "中文下初始预设在叫「默认」")

            Localization.shared.setLanguage(.english)
            expectEqual(L("profile.starter"), "Default", "英文：初始预设名")
            expectEqual(L("editor.reset.confirm", 3), "Delete 3 profile(s)", "英文：带参数词条")
            expectEqual(ProfileStore.makeStarterProfile().name, "Default", "英文下初始预设叫 Default")
            expectEqual(Action.mouseLeftClick.displayName, "Left Click", "英文：动作名")
            expectEqual(ControllerInput.dpadUp.displayName, "D-Pad Up", "英文：按键名")
            expectEqual(ShortcutCatalog.workBuddy.first?.title, "Global Search", "英文：快捷键语义")
        }

        // =====================================================
        // 触摸板 → 指针
        // =====================================================

        suite("DS4 报告布局判定") {
            let short = [UInt8](repeating: 0, count: 9)
            let usb = [UInt8](repeating: 0, count: 64)
            let bt = [UInt8](repeating: 0, count: 78)
            var btPrefix = bt; btPrefix[0] = 0xC0

            expectEqual(DS4TouchParser.layout(reportID: 0x01, payload: short), .limited,
                        "9 字节 0x01 → 精简档位（无触摸板）")
            expect(!DS4TouchParser.layout(reportID: 0x01, payload: short).hasTouchpad,
                   "精简档位不声明触摸板")
            expectEqual(DS4TouchParser.layout(reportID: 0x01, payload: usb), .usbFull,
                        "64 字节 0x01 → USB 完整报告")
            expectEqual(DS4TouchParser.layout(reportID: 0x11, payload: bt), .bluetoothFull(prefix: false),
                        "78 字节 0x11 → 蓝牙完整报告")
            expectEqual(DS4TouchParser.layout(reportID: 0x11, payload: btPrefix), .bluetoothFull(prefix: true),
                        "首字节 0xC0 → 识别 Sony 私有前缀")
            expectEqual(DS4ReportLayout.bluetoothFull(prefix: true).maxEvents, 4,
                        "蓝牙最多 4 个触摸事件")
            expectEqual(DS4ReportLayout.usbFull.maxEvents, 3, "USB 最多 3 个触摸事件")
        }

        suite("DS4 触摸坐标解码与多子帧") {
            let ev = makeTouchEvent(prevX: 990, prevY: 460, prevActive: true, prevTouchID: 1,
                                    curX: 1000, curY: 500, curActive: true, curTouchID: 1)
            let payload = makeUSBReport(events: [ev])
            let frame = DS4TouchParser.parseTouch(payload: payload,
                                                 layout: .usbFull,
                                                 arrivalTime: 100,
                                                 packetInterval: 0.016)
            expect(frame != nil, "USB 完整报告解析成功")
            if let f = frame {
                expectEqual(f.eventCount, 1, "事件数 1")
                expectEqual(f.fingerCount, 1, "活跃触点 1")
                expectEqual(f.samples.count, 2, "一包产生 2 个子帧（prev + cur）")
                expectEqual(f.arrivalTime, 100, "到达时间透传")

                let cur = f.samples.last!
                expect(abs(cur.x - 1000.0 / 1920.0) < 0.0002,
                       "X 解码正确（1000 → \(String(format: "%.4f", cur.x))）")
                expect(abs(cur.y - 500.0 / 943.0) < 0.0002,
                       "Y 解码正确（500 → \(String(format: "%.4f", cur.y))）")

                if f.samples.count == 2 {
                    let prev = f.samples.first!
                    expect(prev.time < cur.time, "prev 子帧时间早于 cur")
                    expect(abs((cur.time - prev.time) - 0.008) < 1e-9,
                           "同一事件内 prev → cur 相隔半步长（packetInterval/2）")
                    expect(abs(prev.x - 990.0 / 1920.0) < 0.0002, "prev X 解码正确")
                }
            }
        }

        suite("DS4 蓝牙报告（含 0xC0 前缀）") {
            let ev = makeTouchEvent(prevX: 100, prevY: 90, prevActive: true, prevTouchID: 3,
                                    curX: 1910, curY: 930, curActive: true, curTouchID: 3)
            let payload = makeBTReport(events: [ev])
            expectEqual(payload.count, 77, "蓝牙 payload 剥离 report ID 后 77 字节")
            expectEqual(DS4TouchParser.layout(reportID: 0x11, payload: payload),
                        .bluetoothFull(prefix: true), "识别为带前缀的蓝牙报告")

            let frame = DS4TouchParser.parseTouch(payload: payload,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 5)
            expect(frame != nil, "蓝牙报告解析成功")
            if let f = frame, let cur = f.samples.last {
                expect(abs(cur.x - 1910.0 / 1920.0) < 0.0002, "12bit X 上限正确（1910）")
                expect(abs(cur.y - 930.0 / 943.0) < 0.0002, "12bit Y 上限正确（930）")
            }
        }

        suite("真机抓包样本（触摸区偏移回归）") {
            let bytes = realIdleBTReport
            expectEqual(bytes.count, 78, "抓包样本 78 字节（含 report ID）")
            let payload = Array(bytes[1...])
            expectEqual(payload.count, 77, "剥离 report ID 后 77 字节")
            expectEqual(DS4TouchParser.layout(reportID: 0x11, payload: payload),
                        .bluetoothFull(prefix: true), "识别为带 0xC0 前缀的蓝牙完整报告")
            expectEqual(DS4ReportLayout.bluetoothFull(prefix: true).touchEventCountOffset, 34,
                        "事件计数在 payload[34]")
            expectEqual(DS4ReportLayout.bluetoothFull(prefix: true).touchEventsOffset, 35,
                        "事件数组从 payload[35] 起")

            // 无手指：事件计数 0，四个槽位是 `00 80 00 00 00 80 00 00 00` 空闲签名
            if let f = DS4TouchParser.parseTouch(payload: payload,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 1) {
                expectEqual(f.eventCount, 0, "空闲报告事件数 0")
                expectEqual(f.samples.count, 0, "空闲报告不产出采样点")
                expectEqual(Int(f.packetCounter), 0, "包计数器取 payload[8] 的 bit2-7")
            } else {
                expect(false, "空闲报告仍应解析成功")
            }

            // 包计数器随包递增：payload[8] 0x00 → 0x04 → 0x08 对应 0 → 1 → 2
            var ticked = payload
            ticked[8] = 0x04
            if let f = DS4TouchParser.parseTouch(payload: ticked,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 1) {
                expectEqual(Int(f.packetCounter), 1, "payload[8] 0x04 → 计数器 1")
            }

            // 在真机形状缓冲区上写入单指按下，验证整条解码链路
            var pressed = payload
            pressed[34] = 1
            let ev = makeTouchEvent(prevX: 1000, prevY: 500, prevActive: true, prevTouchID: 5,
                                    curX: 1100, curY: 550, curActive: true, curTouchID: 5)
            for (k, b) in ev.enumerated() { pressed[35 + k] = b }

            if let f = DS4TouchParser.parseTouch(payload: pressed,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 2) {
                expectEqual(f.eventCount, 1, "改造后事件数 1")
                expectEqual(f.fingerCount, 1, "活跃触点 1")
                expectEqual(f.samples.count, 2, "prev + cur 两个子帧")
                if let cur = f.samples.last {
                    expect(abs(cur.x - 1100.0 / 1920.0) < 0.0002, "真机缓冲区 X 解码正确")
                    expect(abs(cur.y - 550.0 / 943.0) < 0.0002, "真机缓冲区 Y 解码正确")
                }
                if f.samples.count == 2 {
                    expect(abs(f.samples[0].x - 1000.0 / 1920.0) < 0.0002, "prev X 解码正确")
                }
            } else {
                expect(false, "改造后的按下报告应解析成功")
            }
        }

        suite("真机抓包样本：手指触摸中（坐标解码回归）") {
            let bytes = realTouchingBTReport
            expectEqual(bytes.count, 78, "抓包样本 78 字节")
            expectEqual(bytes[35], 4, "绝对偏移 35 = 触摸事件数 4")

            let payload = Array(bytes[1...])
            let frame = DS4TouchParser.parseTouch(payload: payload,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 10,
                                                 packetInterval: 0.016)
            expect(frame != nil, "触摸报告解析成功")
            if let f = frame {
                expectEqual(f.eventCount, 4, "一包 4 个触摸采样")
                expectEqual(f.samples.count, 4, "4 个采样点（第二触点位恒为 inactive）")
                expectEqual(f.fingerCount, 1, "单指 → 1 个活跃触点")

                let xs = f.samples.map { Int(($0.x * 1920).rounded()) }
                let ys = f.samples.map { Int(($0.y * 943).rounded()) }
                expectEqual(xs, [1267, 1282, 1292, 1303], "X 序列与真机一致且单调递增")
                expectEqual(ys, [395, 396, 396, 398], "Y 序列与真机一致")

                expect(f.samples.allSatisfy { $0.y < 1.0 }, "Y 归一化不越界（历史 bug 会到 3.0）")
                expect(f.samples.allSatisfy { $0.touchID == 0 }, "同一根手指 → touchID 恒为 0")

                // 时间：最后一个采样落在到达时刻，整包展在 packetInterval 内
                if let first = f.samples.first, let last = f.samples.last {
                    expect(abs(last.time - 10) < 1e-9, "末个采样 = 到达时刻")
                    expect(abs((last.time - first.time) - 0.012) < 1e-6,
                           "首末采样相隔 3 × (packetInterval/4)")
                }
            }
        }

        suite("DS4 触摸抬起与空帧") {
            // 第二触点位为空（真机固件常态：恒为 80 00 00 00）→ 每个事件只产出 1 个采样
            let ev = makeTouchEvent(prevX: 500, prevY: 500, prevActive: true, prevTouchID: 2,
                                    curX: 500, curY: 500, curActive: false, curTouchID: 2)
            let payload = makeUSBReport(events: [ev])
            if let f = DS4TouchParser.parseTouch(payload: payload, layout: .usbFull, arrivalTime: 1) {
                expectEqual(f.samples.count, 1, "第二触点位为空时只产出 1 个采样")
                expectEqual(f.fingerCount, 1, "第一触点位有效 → 1 个活跃触点")
            } else {
                expect(false, "单触点帧仍应解析成功")
            }

            // 两个触点位都有效 → 同一事件内产出 2 个采样，相隔半个步长
            let both = makeTouchEvent(prevX: 300, prevY: 300, prevActive: true, prevTouchID: 2,
                                      curX: 700, curY: 600, curActive: true, curTouchID: 2)
            let payload2 = makeUSBReport(events: [both])
            if let f = DS4TouchParser.parseTouch(payload: payload2, layout: .usbFull,
                                                 arrivalTime: 1, packetInterval: 0.02) {
                expectEqual(f.samples.count, 2, "双触点位有效 → 2 个采样")
                if f.samples.count == 2 {
                    expect(abs((f.samples[1].time - f.samples[0].time) - 0.01) < 1e-9,
                           "双触点相隔半步长（0.02 / 2）")
                }
            }

            // 事件数为 0：应返回空帧而不是崩溃
            let empty = makeUSBReport(events: [])
            if let f = DS4TouchParser.parseTouch(payload: empty, layout: .usbFull, arrivalTime: 1) {
                expectEqual(f.samples.count, 0, "零事件返回空帧")
            } else {
                expect(false, "零事件应返回空帧")
            }

            // 精简报告：没有触摸数据
            let limited = [UInt8](repeating: 0, count: 9)
            expect(DS4TouchParser.parseTouch(payload: limited, layout: .limited, arrivalTime: 1) == nil,
                   "精简报告不产出触摸帧")
        }

        suite("DS4 CRC32") {
            let vector: [UInt8] = Array("123456789".utf8)
            expectEqual(DS4CRC32.compute(vector[...]), 0xCBF43926, "标准测试向量 CRC-32")
            let empty: [UInt8] = []
            expectEqual(DS4CRC32.compute(empty[...]), 0, "空输入 CRC 为 0")
        }

        suite("双指解析：并行触点 vs 单指时间序列") {
            // 模拟真机双指形态：手指 A 固定在左下，手指 B 在右上移动，
            // 一包 3 个事件 = 3 个时间采样，每事件两个触点位都有效且编号不同。
            let payload = makeTwoFingerBTReport(samples: [
                (ax: 510, ay: 941, bx: 1910, by: 582, idA: 27, idB: 28),
                (ax: 510, ay: 941, bx: 1900, by: 600, idA: 27, idB: 28),
                (ax: 510, ay: 941, bx: 1890, by: 620, idA: 27, idB: 28)
            ])
            expectEqual(DS4TouchParser.layout(reportID: 0x11, payload: payload),
                        .bluetoothFull(prefix: true), "双指报告布局判定正确")

            let frame = DS4TouchParser.parseTouch(payload: payload,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 20,
                                                 packetInterval: 0.015)
            expect(frame != nil, "双指报告解析成功")
            if let f = frame {
                expectEqual(f.fingerCount, 2, "识别出 2 根手指")
                expect(f.isMultiTouch, "isMultiTouch 为真")
                expectEqual(f.samples.count, 0, "多指时 samples 置空（指针冻结）")
                expectEqual(f.fingers.map { $0.touchID }, [27, 28], "按 touchID 升序输出")

                let a = f.fingers[0]
                let b = f.fingers[1]
                expect(abs(a.x - 510.0 / 1920.0) < 0.0002, "手指 A X 正确")
                expect(abs(a.y - 941.0 / 943.0) < 0.001, "手指 A Y 正确")
                // B 取最后一个采样（时间最晚的那次）
                expect(abs(b.x - 1890.0 / 1920.0) < 0.0002, "手指 B 取最新位置 X")
                expect(abs(b.y - 620.0 / 943.0) < 0.0002, "手指 B 取最新位置 Y")
            }

            // 单指形态必须仍然走时间序列，不能被误判成多指
            let single = makeBTReport(events: [
                makeTouchEvent(prevX: 0, prevY: 0, prevActive: false, prevTouchID: 0,
                               curX: 1000, curY: 500, curActive: true, curTouchID: 9),
                makeTouchEvent(prevX: 0, prevY: 0, prevActive: false, prevTouchID: 0,
                               curX: 1010, curY: 500, curActive: true, curTouchID: 9)
            ])
            if let f = DS4TouchParser.parseTouch(payload: single,
                                                 layout: .bluetoothFull(prefix: true),
                                                 arrivalTime: 21) {
                expectEqual(f.fingerCount, 1, "单指只有 1 根手指")
                expect(!f.isMultiTouch, "单指不标记多指")
                expectEqual(f.samples.count, 2, "单指保留完整时间序列")
            } else {
                expect(false, "单指报告应解析成功")
            }
        }

        suite("双指手势：滚动") {
            let g = TwoFingerGestureRecognizer()
            // 第一帧只建立基准，不产生任何输出
            var out = g.ingest([
                FingerContact(touchID: 1, x: 0.4, y: 0.5, time: 0),
                FingerContact(touchID: 2, x: 0.6, y: 0.5, time: 0)
            ])
            expect(!out.isActive, "第一帧建立基准，无输出")

            // 双指一起向上滑（y 减小），间距不变 → 应为滚动，且方向为负（wheel1 < 0）
            var totalY: Int32 = 0
            for i in 1...10 {
                let y = 0.5 - Double(i) * 0.02
                out = g.ingest([
                    FingerContact(touchID: 1, x: 0.4, y: y, time: Double(i) * 0.015),
                    FingerContact(touchID: 2, x: 0.6, y: y, time: Double(i) * 0.015)
                ])
                totalY += out.scrollY
            }
            expect(totalY < 0, "双指上滑 → 负向滚动（\(totalY) px）")
            expect(abs(totalY) > 100, "滚动量级合理（\(abs(totalY)) px）")
            expectEqual(g.gestureKind, "双指滚动", "识别为滚动")

            // 反转滚动方向
            let inverted = TwoFingerGestureRecognizer()
            inverted.config.invertScroll = true
            _ = inverted.ingest([
                FingerContact(touchID: 1, x: 0.4, y: 0.5, time: 0),
                FingerContact(touchID: 2, x: 0.6, y: 0.5, time: 0)
            ])
            var invTotal: Int32 = 0
            for i in 1...10 {
                let y = 0.5 - Double(i) * 0.02
                invTotal += inverted.ingest([
                    FingerContact(touchID: 1, x: 0.4, y: y, time: Double(i) * 0.015),
                    FingerContact(touchID: 2, x: 0.6, y: y, time: Double(i) * 0.015)
                ]).scrollY
            }
            expect(invTotal > 0, "invertScroll 生效，方向反转（\(invTotal) px）")
        }

        suite("双指手势：捏合缩放") {
            let zoomIn = TwoFingerGestureRecognizer()
            _ = zoomIn.ingest([
                FingerContact(touchID: 1, x: 0.45, y: 0.5, time: 0),
                FingerContact(touchID: 2, x: 0.55, y: 0.5, time: 0)
            ])
            var steps = 0
            // 两指张开：间距从 0.1 逐步扩大到 0.6
            for i in 1...20 {
                let d = 0.1 + Double(i) * 0.025
                let out = zoomIn.ingest([
                    FingerContact(touchID: 1, x: 0.5 - d / 2, y: 0.5, time: Double(i) * 0.015),
                    FingerContact(touchID: 2, x: 0.5 + d / 2, y: 0.5, time: Double(i) * 0.015)
                ])
                steps += out.zoomSteps
            }
            expect(steps > 0, "双指张开 → 放大档数（\(steps)）")

            let zoomOut = TwoFingerGestureRecognizer()
            _ = zoomOut.ingest([
                FingerContact(touchID: 1, x: 0.2, y: 0.5, time: 0),
                FingerContact(touchID: 2, x: 0.8, y: 0.5, time: 0)
            ])
            var back = 0
            for i in 1...20 {
                let d = 0.6 - Double(i) * 0.025
                let out = zoomOut.ingest([
                    FingerContact(touchID: 1, x: 0.5 - d / 2, y: 0.5, time: Double(i) * 0.015),
                    FingerContact(touchID: 2, x: 0.5 + d / 2, y: 0.5, time: Double(i) * 0.015)
                ])
                back += out.zoomSteps
            }
            expect(back < 0, "双指收拢 → 缩小档数（\(back)）")
        }

        suite("双指手势：边界与复位") {
            let g = TwoFingerGestureRecognizer()

            // 单指不应产生任何手势
            let one = g.ingest([FingerContact(touchID: 1, x: 0.5, y: 0.5, time: 0)])
            expect(!one.isActive, "单指无手势输出")
            expectEqual(g.gestureKind, "—", "单指复位为无手势")

            // 换一组手指（touchID 变化）必须重建基准，不能把位移当成手势
            _ = g.ingest([
                FingerContact(touchID: 1, x: 0.4, y: 0.5, time: 0),
                FingerContact(touchID: 2, x: 0.6, y: 0.5, time: 0)
            ])
            let switched = g.ingest([
                FingerContact(touchID: 7, x: 0.1, y: 0.1, time: 0.015),
                FingerContact(touchID: 8, x: 0.9, y: 0.9, time: 0.015)
            ])
            expect(!switched.isActive, "touchID 变化 → 重建基准，输出为零")

            // 关闭开关后完全不输出
            let off = TwoFingerGestureRecognizer()
            off.config.isEnabled = false
            _ = off.ingest([
                FingerContact(touchID: 1, x: 0.4, y: 0.5, time: 0),
                FingerContact(touchID: 2, x: 0.6, y: 0.5, time: 0)
            ])
            let closed = off.ingest([
                FingerContact(touchID: 1, x: 0.4, y: 0.1, time: 0.015),
                FingerContact(touchID: 2, x: 0.6, y: 0.1, time: 0.015)
            ])
            expect(!closed.isActive, "开关关闭时不产生手势")
        }

        suite("指针引擎：静止 / 方向 / 死区") {
            let size = CGSize(width: 2560, height: 1080)

            // 静止：位置不变，不应该产生任何位移
            let still = TouchpadPointerEngine()
            for i in 0..<6 {
                let t = Double(i) * 0.012
                still.ingest(makeFrame(x: 0.5, y: 0.5, t: t), arrivalTime: t)
            }
            var stillTotal = 0.0
            for i in 0..<40 {
                let d = still.tick(now: 0.1 + Double(i) / 240.0, screenSize: size)
                stillTotal += abs(d.dx) + abs(d.dy)
            }
            expect(stillTotal < 1.0, "静止时位移为零（实际 \(String(format: "%.3f", stillTotal))）")

            // 向右滑动：累计位移必须为正且量级合理
            let right = TouchpadPointerEngine()
            var rightTotal = 0.0
            for i in 0..<40 {
                let t = 1.0 + Double(i) * 0.012
                let x = 0.20 + Double(i) * 0.015
                right.ingest(makeFrame(x: x, y: 0.5, t: t), arrivalTime: t)
                for k in 0..<3 {
                    rightTotal += right.tick(now: t + Double(k) / 240.0, screenSize: size).dx
                }
            }
            expect(rightTotal > 100, "向右滑动产生正位移（\(Int(rightTotal)) pt）")

            // 向左滑动：方向相反
            let left = TouchpadPointerEngine()
            var leftTotal = 0.0
            for i in 0..<40 {
                let t = 1.0 + Double(i) * 0.012
                left.ingest(makeFrame(x: 0.80 - Double(i) * 0.015, y: 0.5, t: t), arrivalTime: t)
                for k in 0..<3 {
                    leftTotal += left.tick(now: t + Double(k) / 240.0, screenSize: size).dx
                }
            }
            expect(leftTotal < -100, "向左滑动产生负位移（\(Int(leftTotal)) pt）")
            expect(abs(rightTotal + leftTotal) < rightTotal * 0.15,
                   "左右对称（右 \(Int(rightTotal)) / 左 \(Int(-leftTotal))）")

            // 死区：极慢的漂移应被吞掉
            let drifting = TouchpadPointerEngine()
            drifting.config.deadzoneSpeed = 30
            var driftTotal = 0.0
            for i in 0..<60 {
                let t = 1.0 + Double(i) * 0.012
                drifting.ingest(makeFrame(x: 0.5 + Double(i) * 0.00002, y: 0.5, t: t), arrivalTime: t)
                for k in 0..<3 {
                    driftTotal += abs(drifting.tick(now: t + Double(k) / 240.0, screenSize: size).dx)
                }
            }
            expect(driftTotal < 5.0, "低速漂移被死区吃掉（\(String(format: "%.2f", driftTotal)) pt）")
        }

        suite("指针引擎：冻结与重置") {
            let size = CGSize(width: 1920, height: 1080)
            let engine = TouchpadPointerEngine()
            for i in 0..<30 {
                let t = 1.0 + Double(i) * 0.012
                engine.ingest(makeFrame(x: 0.2 + Double(i) * 0.02, y: 0.5, t: t), arrivalTime: t)
                for k in 0..<3 { _ = engine.tick(now: t + Double(k) / 240.0, screenSize: size) }
            }
            expect(engine.isTracking, "滑动中处于追踪状态")

            engine.isFrozen = true
            var frozenMovement = 0.0
            for i in 0..<20 {
                let t = 2.0 + Double(i) * 0.012
                engine.ingest(makeFrame(x: 0.7, y: 0.3, t: t), arrivalTime: t)
                frozenMovement += abs(engine.tick(now: t, screenSize: size).dx)
            }
            expect(frozenMovement == 0, "冻结时不产生位移")

            engine.isFrozen = false
            engine.reset()
            expect(!engine.isTracking, "reset 后退出追踪状态")
            expectEqual(engine.estimatedSpeed, 0, "reset 后速度归零")
        }

        suite("指针引擎：抬手重按光标不跳变") {
            // 用户实际反馈的场景（2026-11-06）：
            // 「手指离开触摸板，再放到另一个区域，鼠标会跳到另一个地方，点击就点错了」
            // 触摸板只输出相对位移，抬指期间的板面距离是空间距离，不是位移。
            let size = CGSize(width: 2560, height: 1080)
            let engine = TouchpadPointerEngine()

            // 第一段：左半边向右滑
            var firstLeg = 0.0
            for i in 0..<25 {
                let t = 1.0 + Double(i) * 0.012
                engine.ingest(makeFrame(x: 0.15 + Double(i) * 0.012, y: 0.30, t: t, touchID: 1),
                              arrivalTime: t)
                for k in 0..<3 {
                    firstLeg += engine.tick(now: t + Double(k) / 240.0, screenSize: size).dx
                }
            }
            expect(firstLeg > 50, "第一段滑动正常产生位移（\(Int(firstLeg)) pt）")

            // 手指抬起：模拟真实蓝牙链路连续发无触摸帧
            for i in 0..<6 {
                let t = 1.40 + Double(i) * 0.0155
                engine.ingest(makeEmptyFrame(t: t), arrivalTime: t)
                _ = engine.tick(now: t, screenSize: size)
            }
            expect(!engine.isTracking, "抬起后立即退出追踪状态")

            // 在右下角完全不同的区域重新按下 —— 这段必须一个点都不动
            var touchDownJump = 0.0
            for i in 0..<8 {
                let t = 1.52 + Double(i) * 0.0155
                engine.ingest(makeFrame(x: 0.86, y: 0.82, t: t, touchID: 9), arrivalTime: t)
                for k in 0..<3 {
                    let d = engine.tick(now: t + Double(k) / 240.0, screenSize: size)
                    touchDownJump += abs(d.dx) + abs(d.dy)
                }
            }
            expect(touchDownJump < 1.0,
                   "在另一区域重新按下，光标原地不动（实际 \(String(format: "%.2f", touchDownJump)) pt）")

            // 重新按下后继续相对滑动，手感不能因此变差
            var secondLeg = 0.0
            for i in 0..<25 {
                let t = 1.72 + Double(i) * 0.012
                engine.ingest(makeFrame(x: 0.86 - Double(i) * 0.012, y: 0.82, t: t, touchID: 9),
                              arrivalTime: t)
                for k in 0..<3 {
                    secondLeg += engine.tick(now: t + Double(k) / 240.0, screenSize: size).dx
                }
            }
            expect(secondLeg < -50, "重按后相对滑动恢复正常（\(Int(secondLeg)) pt）")
        }

        suite("指针引擎：漏发抬帧时靠 touchID 兜底") {
            // 蓝牙丢包会吞掉若干「无触摸帧」，此时收不到抬起信号，
            // 只能靠触点编号变化识别「这是新的一次按下」，否则光标仍会瞬移。
            let size = CGSize(width: 2560, height: 1080)
            let engine = TouchpadPointerEngine()

            for i in 0..<20 {
                let t = 1.0 + Double(i) * 0.012
                engine.ingest(makeFrame(x: 0.12 + Double(i) * 0.012, y: 0.20, t: t, touchID: 3),
                              arrivalTime: t)
                for k in 0..<3 { _ = engine.tick(now: t + Double(k) / 240.0, screenSize: size) }
            }

            // 没有空帧，直接跳到右下角 + 新编号
            var jump = 0.0
            for i in 0..<8 {
                let t = 1.30 + Double(i) * 0.0155
                engine.ingest(makeFrame(x: 0.88, y: 0.85, t: t, touchID: 11), arrivalTime: t)
                for k in 0..<3 {
                    let d = engine.tick(now: t + Double(k) / 240.0, screenSize: size)
                    jump += abs(d.dx) + abs(d.dy)
                }
            }
            expect(jump < 1.0, "编号变化 → 重建基准，不产生跳变（实际 \(String(format: "%.2f", jump)) pt）")
        }

        suite("指针引擎：同一次滑动不会被误判为新按下") {
            // 反向保障：正常连续滑动中绝不能触发基准重建，否则手感会断成一格一格。
            let size = CGSize(width: 2560, height: 1080)
            let engine = TouchpadPointerEngine()
            var total = 0.0
            var ticksSeen = 0
            for i in 0..<40 {
                // 每包 15.5ms 走 0.02 板宽 ≈ 1.3 板宽/秒，属于正常快速滑动范围
                let t = 1.0 + Double(i) * 0.0155
                engine.ingest(makeFrame(x: 0.10 + Double(i) * 0.02, y: 0.5, t: t, touchID: 21),
                              arrivalTime: t)
                for k in 0..<3 {
                    total += engine.tick(now: t + Double(k) / 240.0, screenSize: size).dx
                    ticksSeen += 1
                }
            }
            expect(engine.isTracking, "连续滑动全程保持追踪")
            expect(total > 500, "快速滑动位移量正常（\(Int(total)) pt）")
            // 若被误重置，位移会明显缩水（每次重置丢一整个基准周期）
            expect(total > Double(ticksSeen) * 3, "没有因误重置而丢位移")
        }

        suite("指针引擎：配置边界") {
            let e = TouchpadPointerEngine()
            expectEqual(e.config.sensitivity, PointerConfig().sensitivity, "默认灵敏度")
            e.config.smoothing = 1.0
            e.config.deadzoneSpeed = 0
            expect(e.config.smoothing <= 1.0, "平滑系数在合法范围")
            expect(e.config.maxStepPerTick > 0, "单 tick 上限为正")
        }

        // =====================================================
        // Final
        // =====================================================
        print("")
        print("=================================================")
        print("测试结果：")
        print("  通过：\(passed)")
        print("  失败：\(failed)")
        print("  合计：\(passed + failed)")
        if failed == 0 {
            print("  ✓ 全部通过")
            exit(0)
        } else {
            print("  ✗ 有失败用例")
            exit(1)
        }
    }
}

// MARK: - 触摸板测试辅助

/// 编码一个触摸事件（9 字节：timestamp + 触点 A 4 字节 + 触点 B 4 字节）
func makeTouchEvent(prevX: Int, prevY: Int, prevActive: Bool, prevTouchID: UInt8,
                    curX: Int, curY: Int, curActive: Bool, curTouchID: UInt8,
                    timestamp: UInt8 = 0) -> [UInt8] {
    // 真机字节序：id / X 低 8 位 / (Y 低 4 位 << 4 | X 高 4 位) / Y 高 8 位
    func encode(_ x: Int, _ y: Int, _ active: Bool, _ id: UInt8) -> [UInt8] {
        let idByte = (id & 0x7F) | (active ? 0x00 : 0x80)
        let xLow = UInt8(x & 0xFF)
        let mixed = UInt8(((y & 0x0F) << 4) | ((x >> 8) & 0x0F))
        let yHigh = UInt8((y >> 4) & 0xFF)
        return [idByte, xLow, mixed, yHigh]
    }
    var out: [UInt8] = [timestamp]
    out += encode(prevX, prevY, prevActive, prevTouchID)
    out += encode(curX, curY, curActive, curTouchID)
    return out
}

/// 构造 64 字节 USB 完整报告（payload 不含 report ID）
func makeUSBReport(events: [[UInt8]]) -> [UInt8] {
    var p = [UInt8](repeating: 0, count: 64)
    p[0] = 128; p[1] = 128; p[2] = 128; p[3] = 128
    p[34] = UInt8(min(events.count, 3))
    var i = 35
    for e in events {
        for b in e {
            if i < 64 { p[i] = b; i += 1 }
        }
    }
    return p
}

/// 构造蓝牙完整报告 payload（77 字节，含 0xC0 0x00 前缀，已剥离 report ID）
/// 偏移与真机抓包校准结果一致：事件计数 payload[34]，事件数组 payload[35..]
func makeBTReport(events: [[UInt8]]) -> [UInt8] {
    var body = [UInt8](repeating: 0, count: 75)
    body[0] = 128; body[1] = 128; body[2] = 128; body[3] = 128
    body[32] = UInt8(min(events.count, 4))
    var i = 33   // payload[35] 对应 body[33]（body 比 payload 少 2 字节前缀）
    for e in events {
        for b in e {
            if i < 75 { body[i] = b; i += 1 }
        }
    }
    return [0xC0, 0x00] + body
}

/// 真机抓包样本（2026-11-06，Mac mini + 蓝牙 DS4 0x09CC，无手指触摸）
/// 含 report ID，78 字节。用于锁定触摸区真实偏移，防止后续改动再次错位。
let realIdleBTReport: [UInt8] = [
    0x11, 0xC0, 0x00, 0x7D, 0x7E, 0x7F, 0x80, 0x08, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x16, 0xFD, 0x04,
    0x00, 0x01, 0x00, 0xFE, 0xFF, 0x40, 0x03, 0x38, 0x20, 0xA7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x09, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00,
    0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00,
    0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC7, 0xFA, 0x75, 0x97
]

/// 真机抓包样本 #2（同一台设备，手指正在触摸板上缓慢移动）
/// 一包 4 个触摸事件，X 应单调递增 1267 → 1282 → 1292 → 1303，Y 稳定在 395~398。
/// 这份样本钉死了三个易错点：事件起点 payload[35]、包内事件是时间采样而非多指槽位、
/// 触点 4 字节序为 id / X低 / 混合 / Y高。
let realTouchingBTReport: [UInt8] = [
    0x11, 0xC0, 0x00, 0x7D, 0x7E, 0x7F, 0x7F, 0x08, 0x00, 0xC8, 0x00, 0x00, 0x27, 0x88, 0xF7, 0x3D,
    0x00, 0xF2, 0xFF, 0x04, 0x00, 0x98, 0xFD, 0xCC, 0x01, 0xF8, 0xDE, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x09, 0x00, 0x00, 0x04, 0xF2, 0x00, 0xF3, 0xB4, 0x18, 0x80, 0x00, 0x00, 0x00, 0xFA, 0x00, 0x02,
    0xC5, 0x18, 0x80, 0x00, 0x00, 0x00, 0x01, 0x00, 0x0C, 0xC5, 0x18, 0x80, 0x00, 0x00, 0x00, 0x09,
    0x00, 0x17, 0xE5, 0x18, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD9, 0x5E, 0x0A, 0xD6
]

/// 构造单点单采样的触摸帧
func makeFrame(x: Double, y: Double, t: Double, touchID: Int = 1) -> TouchpadFrame {
    TouchpadFrame(
        samples: [TouchpadSample(time: t, x: x, y: y, slot: 0, active: true, touchID: touchID)],
        fingers: [FingerContact(touchID: touchID, x: x, y: y, time: t)],
        eventCount: 1,
        packetCounter: 0,
        arrivalTime: t
    )
}

/// 构造「手指已离开触摸板」的空帧（真机上对应 eventCount == 0 的报告）
func makeEmptyFrame(t: Double) -> TouchpadFrame {
    TouchpadFrame(samples: [], fingers: [], eventCount: 0, packetCounter: 0, arrivalTime: t)
}

/// 构造双指帧（用于手势识别器测试）
func makeTwoFingerFrame(idA: Int, xA: Double, yA: Double,
                        idB: Int, xB: Double, yB: Double,
                        t: Double) -> TouchpadFrame {
    TouchpadFrame(
        samples: [],
        fingers: [
            FingerContact(touchID: idA, x: xA, y: yA, time: t),
            FingerContact(touchID: idB, x: xB, y: yB, time: t)
        ],
        eventCount: 1,
        packetCounter: 0,
        arrivalTime: t
    )
}

/// 构造双指报告：每个事件里触点位 A 与 B 都有效且编号不同。
/// - A 对应真实固件里的「第一根手指」
/// - B 对应「第二根手指」
/// 一包里多个事件 = 多个时间采样。
func makeTwoFingerBTReport(
    samples: [(ax: Int, ay: Int, bx: Int, by: Int, idA: UInt8, idB: UInt8)]
) -> [UInt8] {
    let events = samples.map { s in
        makeTouchEvent(prevX: s.ax, prevY: s.ay, prevActive: true, prevTouchID: s.idA,
                       curX: s.bx, curY: s.by, curActive: true, curTouchID: s.idB)
    }
    return makeBTReport(events: events)
}
