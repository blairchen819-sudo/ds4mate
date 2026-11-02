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
        // Suite 3: Profile + BuiltInProfiles
        // =====================================================
        suite("BuiltInProfiles") {
            let all = BuiltInProfiles.makeAll()
            expectEqual(all.count, 3, "内置 Profile 总数 3")

            let defaultProfile = BuiltInProfiles.makeDefault()
            expectEqual(defaultProfile.name, "默认", "默认 Profile 名称")
            expect(defaultProfile.isBuiltin, "默认 Profile isBuiltin=true")
            for input in ControllerInput.allCases {
                let hasBinding = defaultProfile.binding(for: input) != nil
                expect(hasBinding, "默认 Profile 有 \(input.displayName) 绑定")
            }

            let mediaProfile = BuiltInProfiles.makeMedia()
            expectEqual(mediaProfile.name, "媒体遥控", "媒体 Profile 名称")
            if let binding = mediaProfile.binding(for: .cross) {
                if case .mediaKey(let m) = binding.action {
                    expectEqual(m, .playPause, "媒体 × 键 = playPause")
                } else {
                    print("  ✗ 媒体 × 键不是媒体键")
                    failed += 1
                }
            }

            let presProfile = BuiltInProfiles.makePresentation()
            expectEqual(presProfile.name, "演示", "演示 Profile 名称")
            if let binding = presProfile.binding(for: .cross) {
                if case .keyPress(let code, _) = binding.action {
                    expectEqual(code, 124, "演示 × 键 = Right Arrow (124)")
                } else {
                    print("  ✗ 演示 × 键不是 keyPress")
                    failed += 1
                }
            }

            // OPEN-DECISIONS R-5：PS 键在所有内置 Profile 中都禁用
            for profile in BuiltInProfiles.makeAll() {
                if let binding = profile.binding(for: .ps) {
                    if case .none = binding.action {
                        expect(true, "\(profile.name) PS 键禁用")
                    } else {
                        print("  ✗ \(profile.name) PS 键应该禁用，实际：\(binding.action)")
                        failed += 1
                    }
                }
            }

            // Options 键在所有内置 Profile 中都是 exitApp
            for profile in BuiltInProfiles.makeAll() {
                if let binding = profile.binding(for: .options) {
                    if case .exitApp = binding.action {
                        expect(true, "\(profile.name) Options 键 = exitApp")
                    } else {
                        print("  ✗ \(profile.name) Options 键应该 exitApp，实际：\(binding.action)")
                        failed += 1
                    }
                }
            }
        }

        // =====================================================
        // Suite 4: ProfileStore
        // =====================================================
        suite("ProfileStore") {
            let store = ProfileStore()
            let loaded = store.loadAll()
            // 内置固定 3 套；用户可能另有自定义预设，所以只校验内置数量
            expectEqual(loaded.filter { $0.isBuiltin }.count, 3, "内置 Profile 有 3 个")

            expectThrows({
                try store.save(BuiltInProfiles.makeDefault())
            }, "不能保存内置 Profile")

            expectThrows({
                try store.delete(BuiltInProfiles.makeDefault())
            }, "不能删除内置 Profile")

            // 保存并加载自定义
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
                expect(found != nil, "保存的自定义 Profile 重新加载成功")
                if let found = found {
                    expectEqual(found.name, custom.name, "自定义 Profile 名称一致")
                    expectEqual(found.bindings.count, 1, "自定义 Profile 绑定数 1")
                }
                try? store.delete(custom)
            } catch {
                print("  ✗ 保存/加载自定义失败：\(error)")
                failed += 1
            }
        }

        // =====================================================
        // Suite 4b: ProfileStore.saveAs
        // =====================================================
        suite("ProfileStore.saveAs") {
            let store = ProfileStore()
            let source = BuiltInProfiles.makeDefault()
            let name = "另存测试-\(UUID().uuidString.prefix(8))"
            do {
                let copy = try store.saveAs(source, name: name)
                expectEqual(copy.name, name, "另存为名称正确")
                expect(!copy.isBuiltin, "另存为得到自定义 Profile")
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
        // Suite 5: JSON Resource
        // =====================================================
        suite("JSON Resource 文件") {
            // 找到 build 目录
            let testExecutableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            let buildDir = testExecutableURL.deletingLastPathComponent()
            let resourcesDir = buildDir.appendingPathComponent("DS4Mate.app/Contents/Resources")

            let resourceFiles = ["default", "media", "presentation"]
            for name in resourceFiles {
                let jsonURL = resourcesDir.appendingPathComponent("\(name).json")
                if FileManager.default.fileExists(atPath: jsonURL.path) {
                    do {
                        let data = try Data(contentsOf: jsonURL)
                        let profile = try JSONDecoder().decode(Profile.self, from: data)
                        expectEqual(profile.isBuiltin, true, "\(name).json isBuiltin=true")
                        expectEqual(profile.bindings.count, 22, "\(name).json 绑定数 22")
                        print("    → 名称: \(profile.name), 死区: \(profile.parameters.deadzone)")
                    } catch {
                        print("  ✗ \(name).json 解析失败：\(error)")
                        failed += 1
                    }
                } else {
                    print("  ⚠ \(name).json 不存在（resources 目录可能不完整）")
                }
            }
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
