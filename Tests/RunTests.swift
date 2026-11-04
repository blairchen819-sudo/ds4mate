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
