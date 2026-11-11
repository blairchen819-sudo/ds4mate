# DS4Mate

**Turn a PS4 DualShock 4 into a mouse, keyboard and shortcut remote for your Mac.**

Browse from the couch, move between apps, or control an AI coding session without reaching for the keyboard. DS4Mate is a native SwiftUI menu bar app with visual button mapping, switchable profiles, and an English / Simplified Chinese interface. It runs as a macOS app, with no terminal needed for everyday use.

[Download v1.2.0](https://github.com/blairchen819-sudo/ds4mate/releases/tag/v1.2.0) · [Quick start](#quick-start) · [Example profiles](#example-profiles) · [Build from source](#build-from-source)

## What you can do

- **Browse and control your desktop:** use the right stick as a mouse, the left stick to scroll, and controller buttons to click, go back, or open window controls.
- **Use the controller's touchpad:** slide to move the pointer, press to left-click, or use two fingers to scroll and send zoom shortcuts. Source builds also offer optional tap-to-click.
- **Keep an AI conversation within reach:** the included WorkBuddy profile maps buttons to send a message, delete text, move between tasks and switch desktops.
- **Control a coding session:** the included Orca profile maps buttons to Enter, Tab, worktree navigation, tabs and voice input. Check the mappings before using it in a live terminal: Enter can execute a command.
- **Make your own remote:** map 22 controller inputs, save a named profile for each workflow, and switch profiles from the menu bar or a controller button.

App-specific shortcuts depend on the target app and its settings. DS4Mate sends the configured input to your Mac; it does not understand the command or message you are sending.

## Release status and compatibility

| | Public download: v1.2.0 | Current source on `main` |
|---|---|---|
| Stick/button mapping, profile management, touchpad pointer and two-finger gestures | Included | Included |
| Onboarding explains both required permissions | Not included | Included |
| JSON profile import/export in Settings | Not included | Included |
| New starter profile leaves Options unbound | No: Options quits immediately | Yes |
| Optional tap-to-click | Not included | Included, off by default |

The downloadable archive is [`DS4Mate-v1.2.0.zip`](https://github.com/blairchen819-sudo/ds4mate/releases/download/v1.2.0/DS4Mate-v1.2.0.zip). Build from source to use the unreleased improvements. Existing saved profiles keep their mappings; updating the app does not automatically remove an old Options-to-quit binding.

- **Controller:** PS4 DualShock 4 over Bluetooth. USB and PS5 DualSense are not supported or hardware-validated, even though some device/report handling exists in the source.
- **Mac:** the release and bundled build script target Apple Silicon (`arm64`). Intel Macs have not been validated.
- **macOS:** macOS 13 Ventura is the declared minimum in `Package.swift` and `Info.plist`. Development and testing have been on macOS 26; older supported versions, including macOS 13 and 14, remain unverified.
- **Signing:** the public release is ad-hoc signed, not Apple-notarized, and has no Developer ID signature. Download only from this repository's releases and decide whether you trust it before opening.

**Hardware validation recorded on November 11, 2026:** pointer movement and basic tap-to-click were confirmed on a real DualShock 4 using the current source. Dragging, multi-finger edge cases, physical-click suppression, packet-loss behavior, a second Mac, Intel Macs and older macOS versions still need broader hardware testing. Automated tests do not replace those checks.

## Quick start

1. Download and unzip the [v1.2.0 release](https://github.com/blairchen819-sudo/ds4mate/releases/tag/v1.2.0).
2. Move `DS4Mate.app` to `/Applications` or another stable location. On first launch, macOS may block this unnotarized app. If you trust the download, use Finder's **right-click → Open**, or **System Settings → Privacy & Security → Open Anyway** where offered, and confirm the system prompt. Do not disable Gatekeeper globally.
3. Choose **English** in the first-run language picker and follow the setup screens. The app lives in the menu bar, not the Dock.
4. In **System Settings → Privacy & Security**, enable `DS4Mate.app` under **both Accessibility and Input Monitoring**. The v1.2.0 onboarding does not explain both, so check each list yourself.
5. Hold **Share + PS** until the controller's light bar flashes. In **System Settings → Bluetooth**, select **DUALSHOCK 4 Wireless Controller**. DS4Mate detects the paired controller automatically.
6. Move the **right stick** to move the pointer, the **left stick** to scroll, press **×** to left-click and **○** to right-click.
7. Open the menu bar icon to pause input, change profiles, open settings or quit.

**v1.2.0 warning:** Options in the starter profile quits the app on press. There is no long-press delay. Remap it in the editor if you want to avoid accidental exits, and use the menu bar to quit.

### Permissions and troubleshooting

| Permission | Why it is needed | What DS4Mate can check |
|---|---|---|
| Accessibility | Generate mouse and keyboard events; operate supported app controls | The app checks its authorization status |
| Input Monitoring | Receive the controller's HID reports | The app opens the settings page but does not verify the permission state |

- **Connected, but nothing happens:** confirm both permissions, ensure input is enabled in the menu bar, and check the active profile. If HID reports stay at zero, check Input Monitoring first.
- **Buttons work, but the touchpad does not:** enable **Settings → General → Touchpad → Use touchpad as mouse**. The diagnostics should show full Bluetooth reports; limited `0x01` reports do not contain touch coordinates.
- **A rebuild stops receiving input:** ad-hoc signing can change the app's identity. Recheck the permissions for the exact app you are running.
- **An app shortcut does the wrong thing:** check which app has focus and edit the binding to match that app's shortcuts.

## Touchpad controls

Turn on **Settings → General → Touchpad → Use touchpad as mouse**.

| Gesture | Action |
|---|---|
| Slide one finger | Move the pointer using relative movement |
| Lift and place the finger elsewhere | Start a new movement without treating the gap as pointer travel |
| Physically press the touchpad | Left mouse button |
| Slide two fingers | Scroll, when two-finger gestures are enabled |
| Pinch or spread two fingers | Send `⌘-` or `⌘=` zoom shortcuts |
| Quickly touch and lift one finger | One left-click, only with **Tap to click** enabled in a source build |

Sensitivity, smoothing, dead zone, gesture scroll speed, zoom sensitivity and scroll direction are adjustable. The pointer pauses while two fingers are down.

**Touchpad mode takes over the touchpad button.** Its normal profile mapping is bypassed, so one press does not also open a window control or terminal. Leave touchpad mouse mode off if you want to keep that binding.

Tap-to-click is **off by default**. Its default limits are 180 ms and 2% of the touchpad width, both adjustable. A long touch, excessive movement, a second finger, a physical press or a changed touch ID cancels the tap candidate. The implementation emits one click for an accepted tap and suppresses a physical rebound within 150 ms. Those edge cases still need broader real-device validation.

Zoom uses keyboard shortcuts, not native macOS magnify events. The result depends on the foreground app, which may assign those shortcuts to something other than zoom. Disable two-finger gestures if that conflicts with your workflow. Three-finger gestures are not implemented.

See [Touchpad implementation and tuning](docs/touchpad-mouse.md) for the technical details.

## Problems the implementation addresses

These are implemented behaviors, not a claim that every controller and macOS version has been tested.

| Problem | Approach in DS4Mate |
|---|---|
| The project's macOS 26 setup did not receive PS4 events through GameController | Read controller input directly with `IOHIDManager` instead. See [HIDControllerService](Sources/DS4Mate/Services/HIDControllerService.swift). |
| Bluetooth buttons worked, but touch coordinates were missing | Request feature report `0x02` to switch the DS4 from limited reports to full Bluetooth reports containing touch samples. |
| Repositioning a finger could make the pointer jump | Clear the movement baseline on lift, touch-ID changes and large discontinuities. See [TouchpadPointerEngine](Sources/DS4Mate/Services/TouchpadPointerEngine.swift). |
| One touchpad press could both click and trigger its mapped action | Route that button exclusively to mouse input while touchpad mouse mode is enabled. See [ControllerService](Sources/DS4Mate/Services/ControllerService.swift). |
| Users could miss Input Monitoring or accidentally quit with Options | Current source explains both permissions and creates new starter profiles with Options unbound. Saved profiles are preserved. |

The touchpad pipeline consumes multiple samples per report, interpolates them, applies velocity-adaptive smoothing and schedules pointer output at 240 Hz. That is an output timer setting, not a measured end-to-end latency or hardware sampling-rate guarantee.

## Profiles and button mapping

Open the visual editor from the menu bar, choose a controller input and assign an action. Supported actions include mouse movement/clicks/scrolling, keyboard shortcuts, held modifier keys, system shortcuts, profile switching and supported app actions. **Media-key actions appear in the model but are not implemented**, so do not rely on them for playback or volume control.

- The first launch creates an editable starter profile. Profiles are user data, not locked presets.
- Use **Save As** to create another named profile; choose it in the editor or menu bar.
- Assign a global profile-switch button to keep the same switch control across profiles. Touchpad mouse mode still takes priority over the touchpad button.
- Delete profiles individually; the UI prevents deleting the last one.
- In current source, **Settings → General → Data → Export Profile / Import Profile** transfers JSON files. Import creates a fresh profile ID instead of overwriting an existing profile.

Profiles are stored locally at:

```text
~/Library/Application Support/DS4Mate/profiles/
```

DS4Mate stores settings locally and has no account, cloud sync or in-app update service. Profile import reads the file you select. Qwen and iFlytek actions use Accessibility to operate those apps; their own network and privacy behavior is separate from DS4Mate.

### Example profiles

Two editable profiles are included:

- [`examples/workbuddy.json`](examples/workbuddy.json): pointer control, messaging, task navigation and desktop switching in WorkBuddy.
- [`examples/orca.json`](examples/orca.json): pointer control, Enter/Tab, worktree and tab navigation, and voice input in Orca.

**Source builds:** use **Import Profile** in Settings for each JSON file. Each import creates a new copy, so importing again creates another profile.

**v1.2.0:** launch the app once to create its profile folder, then quit it. From the repository directory, copy the examples with their profile IDs as filenames:

```bash
profile_dir="$HOME/Library/Application Support/DS4Mate/profiles"
mkdir -p "$profile_dir"
cp -i examples/workbuddy.json "$profile_dir/57FB2566-E9FA-4BBC-84B7-4E50240995F3.json"
cp -i examples/orca.json "$profile_dir/75925C45-00EF-404D-ACDD-91F3F0BCBA84.json"
```

Restart DS4Mate and select the profile from the menu bar. `cp -i` asks before replacing an existing file; do not overwrite a profile you have customized without backing it up. If you previously copied the files under different names, avoid keeping multiple JSON files with the same profile ID.

| Controller input | WorkBuddy profile | Orca profile |
|---|---|---|
| Right stick | Move pointer | Move pointer |
| Left stick / L2 | Scroll | Scroll |
| R2 / ○ | Right-click | Right-click |
| × | Delete | Delete |
| □ | Left-click | Enter: execute command |
| △ | Enter: send message | Tab: completion |
| L1 | `⌘[` | `⇧⌘[` |
| R1 | `⌘]` | App Exposé |
| L3 | `⇧⌘B`: toggle sidebar | `⌘⌥T`: new agent tab |
| R3 | Left-click | Left-click |
| D-pad up / down | Up / Down | `⌘↑` / `⌘↓`: worktree navigation |
| D-pad left / right | Previous / next desktop | `⇧⌘[` / `⇧⌘]`: tab navigation |
| Touchpad press, with touchpad mouse off | App Exposé | `⌘⌥A`: floating terminal |
| Options | Hold Option while pressed | `⌘E`: voice input |
| Share | Next profile | Next profile |
| PS | Unbound | Next profile |

The JSON files are the source of truth. In particular, the WorkBuddy touchpad and Orca R1 bindings use **App Exposé**, not Mission Control.

## App integrations

- **Qwen:** actions toggle voice calls and microphone mute through Accessibility, with desktop/window switching logic.
- **iFlytek input method:** an action finds its voice panel and toggles the microphone through Accessibility.

These integrations require the corresponding app and depend on its UI layout. App updates, window state or missing Accessibility authorization can break them.

## Build from source

You need macOS, the Xcode command-line toolchain with Swift 5.9 or later, a macOS SDK, and Python 3 for the localization check. The bundled script targets Apple Silicon.

```bash
git clone https://github.com/blairchen819-sudo/ds4mate.git
cd ds4mate
./scripts/build.sh
open build/DS4Mate.app
```

**Read [`scripts/build.sh`](scripts/build.sh) before running it.** It clears the repository's `build/` directory, compiles the app and smoke-test executable, assembles and signs the app, runs tests, then launches and stops the app for a short startup check. It can stop an already-running DS4Mate instance. App launch can receive controller input, so this is not a read-only documentation check.

For local signing, the script prefers an existing **DS4Mate Local Signing** identity and otherwise falls back to ad-hoc signing. Its optional dedicated-keychain path unlocks that keychain and changes the user keychain search list when configured. Do not run the full script merely to check documentation or translations.

After opening the built app, complete the same permissions and Bluetooth setup as in Quick start. Choose the language on first launch; change it later in **Settings → General** without restarting.

### Checks and tests

Check that English and Simplified Chinese UI keys match, without building or launching the app:

```bash
python3 scripts/check-i18n.py
```

After a fresh build, run the custom smoke-test executable:

```bash
./build/DS4MateTests
```

[`Tests/RunTests.swift`](Tests/RunTests.swift) covers model and profile behavior, JSON import/export, shortcut and localization checks, and touch parsing/pointer/gesture/tap logic, including captured-report regressions. Use the result from your current build rather than a historical test count. `Package.swift` has no test target, so `swift test` is not the test entry point.

A passing smoke suite does not verify Bluetooth hardware, macOS permissions, actual input delivery, all gestures or third-party app integrations. Keep those checks separate.

## Architecture and documentation

```text
DualShock 4 over Bluetooth
  → IOHIDManager → HID report parser
      → Button/stick mappings → EventSynthesizer
      → Touch samples → Pointer/gesture/tap engines → TouchpadMouseService
  → macOS mouse and keyboard events
  → Foreground app
```

The app uses SwiftUI for its menu bar and settings, CoreGraphics for event synthesis, Codable JSON for profiles and local preferences for settings. The runtime localization dictionary switches between English and Simplified Chinese without a restart.

| Path | Contents |
|---|---|
| `Sources/DS4Mate/App/` | App entry point, shared state, localization and first-run setup |
| `Sources/DS4Mate/Models/` | Controller inputs, actions, profiles and shortcut definitions |
| `Sources/DS4Mate/Services/` | HID input, profile storage, event synthesis and touchpad engines |
| `Sources/DS4Mate/Views/` | Menu, editor, settings and onboarding |
| `Tests/RunTests.swift` | Custom smoke-test harness |
| `examples/` | WorkBuddy and Orca profile JSON |
| `tools/hid-probe/` | Standalone HID diagnostic tool, separate from the app build |
| `scripts/` | Build and localization checks |
| `build/` | Generated executable, app bundle and test executable |

Further reading (some supporting documents are in Chinese and include historical plans):

- [Product specification](docs/SPEC.md) and [resolved product decisions](docs/OPEN-DECISIONS.md)
- [Architecture](docs/architecture.md), [UI design](docs/DESIGN.md) and [design system](docs/design-system/MASTER.md)
- [Product research](docs/research/PRD-v0.1.md), [design tokens](docs/design-tokens.json) and [architecture decision index](docs/adr-index.md)
- [Touchpad implementation and tuning](docs/touchpad-mouse.md)
- [Planned demo recording](docs/DEMO-SHOTLIST.md): a real-device video, GIF or screenshot demo is still pending

## Known limits and next steps

- Bluetooth DualShock 4 is the supported path. USB, DualSense, Xbox and Switch Pro support remain future work.
- Media-key output and three-finger touchpad gestures are not implemented.
- Zoom and desktop/app shortcuts depend on macOS and app shortcut settings.
- The release is not notarized or distributed through the Mac App Store.
- Hardware and OS coverage is limited as described above; no broad compatibility claim is intended.

Delivered milestones include Bluetooth/button mapping and editable profiles, bilingual UI and example profiles, then the v1.2.0 touchpad pointer, two-finger gestures and iFlytek action. Current source adds tap-to-click, profile import/export, clearer permissions setup and the unbound Options starter mapping.

Future ideas include three-finger gestures, expanded stick tuning, USB and additional controllers, and macro support. These are roadmap ideas, not shipped features or release-date commitments.

## License

[MIT](LICENSE)
