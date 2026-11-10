# Demo shot list — 20–30 second real recording

**Status: pending real recording.** There is no demo video, GIF, or screenshot in this repository.
The final asset must be captured on real hardware (a real DualShock 4 over Bluetooth) and placed at
`docs/media/demo.mp4` (or `docs/media/demo.gif`). Do not substitute a mock window, animated mockup,
simulated controller input, or fabricated latency.

Target length: **26 seconds** (hard limit 20–30 s).

## Preconditions

- Real **PS4 DualShock 4** (`0x09CC` / `0x05C4`), charged and paired over **Bluetooth**. Do not use DualSense.
- Choose and label the exact build being recorded. To show the new dual-permission Settings UI, use a locally built **unreleased working-tree build** after manual validation; the public **v1.2.0** ZIP does not include that UI. If recording v1.2.0 instead, omit the new-UI cutaway and do not imply unreleased features are in the download. Keep the app at a stable path.
- **Accessibility** and **Input Monitoring** both granted:
  System Settings → Privacy & Security → Accessibility / Input Monitoring.
- Default starter profile active (`Default`) and mapping **enabled** in the menu bar.
- A second profile with a different, non-personal name for the profile-switch shot.
- Touchpad-mouse optional: Settings → General → Touchpad → “Touchpad as mouse”.
- Clean desktop: no personal files, usernames, paths, browser tabs, email, messages, or notifications.
- Use a scratch folder and a neutral long document (e.g. lorem ipsum) as click/scroll targets.
- Recording region 16:9, pointer visible; hide the Dock and disable notification banners.
- Record in one take if possible. If a segment needs a separate take, keep the same desktop and scaling.

## Second-by-second shot list

| Time | Shot | What must be visible | Notes |
|------|------|----------------------|-------|
| 0.0–3.0 | Menu bar + active profile | Click the DS4Mate menu-bar icon; show connection status, active profile name (`Default`), HID report count, and the mapping toggle | Keep unrelated menu-bar items out of frame |
| 3.0–6.0 | Right stick = pointer | Move the right stick in a slow circle; the pointer travels across the neutral desktop | Real pointer motion only; no cursor overlay or post-produced cursor |
| 6.0–8.0 | × = left click | Press × on a neutral target (e.g. select a file in the scratch Finder folder) | Show the actual selection/click result |
| 8.0–10.0 | ○ = right click | Press ○ on the scratch folder/desktop; the context menu opens; dismiss with × or Esc | Keep menu contents generic |
| 10.0–13.0 | Left stick = scroll | Scroll the long neutral document up and down | Show content moving, not just a caption |
| 13.0–15.0 | Share = screenshot selection | Press Share; the macOS screenshot crosshair/selection UI appears; cancel with Esc | Do not save a screenshot to the desktop; Esc avoids stray files |
| 15.0–18.0 | Touchpad two-finger scroll / pinch (if enabled) | Enable “Touchpad as mouse”; two-finger scroll the document, then pinch to zoom (`⌘=` / `⌘-`) | Cut this segment if touchpad mouse is disabled. Do not fake it |
| 18.0–21.0 | Profile switch + mapping toggle | Cycle to a second profile from the menu bar or the configured global switch key; show the profile name change; toggle mapping off/on | Use two profiles with visibly different, non-personal names |
| 21.0–26.0 | Onboarding / permissions | Show the 4-step onboarding (welcome → permissions → pairing → try) end to end, or a 5 s cutaway of Settings → Permissions with both Accessibility and Input Monitoring entries | Record separately if needed; no system account details |

If a segment runs long, shorten the pointer and scroll shots first. Do not exceed 30 s.

## Explicit exclusions

Do **not** show or claim any of the following:

- **Media keys** — `Action.mediaKey` is unimplemented and only logs `mediaKey not implemented`. Use system shortcuts instead.
- **USB wired** — not supported or hardware-validated in v1.2 (roadmap v2.0). A USB report-layout parser exists in code but has not been validated on hardware.
- **DualSense** — unsupported. The service matches PID `0x0CE6`, but the parser is DS4-specific and DualSense is unvalidated.
- **Notarization, Developer ID, or a clean double-click install** — the published build is ad-hoc signed and not notarized; first launch requires right-click → Open.
- **Any feature not present in the starter profile or Settings** — no staged UI, no simulated controller input, no fake permission dialogs.

## Recording and encoding

- Aspect ratio: **16:9**.
- Resolution: **1280×720** or **1920×1080** (both 16:9).
- Frame rate: **30 fps**.
- Codec/container: **H.264 MP4** (`docs/media/demo.mp4`) preferred; an **optimized GIF** (`docs/media/demo.gif`) only if a static host requires it.
- Size target: MP4 **≤ 8 MB**; GIF **≤ 5 MB**.
- Captions: burned in or sidecar. Name the action and the button at each segment; keep them short and accurate.
- Timing: **do not speed up** pointer, click, scroll, or profile-switch footage. If idle time is trimmed, keep input-to-result latency visible and note the trim.
- Audio: none required; if included, no voice or personal audio.
- Privacy: scrub desktop, Dock, menu bar, notifications, usernames, paths, and window titles before export.
- Cleanup: do not commit raw takes, screen recordings containing personal data, or editor project files.

## Acceptance checklist

- [ ] Captured on a real DualShock 4 over Bluetooth; no simulated input.
- [ ] 20–30 s, 16:9, 30 fps, H.264 MP4 or optimized GIF.
- [ ] Accessibility and Input Monitoring granted before recording; no permission errors on screen.
- [ ] Right-stick pointer, × left click, ○ right click, left-stick scroll, Share screenshot selection, and profile switch are all real.
- [ ] Touchpad segment is either real (enabled) or cut; never faked.
- [ ] No media-key, USB, DualSense, notarization, or clean-install claims.
- [ ] No personal data, notifications, usernames, or private window titles.
- [ ] File is `docs/media/demo.mp4` (or `demo.gif`) and within the size target.
- [ ] README “Demo (pending real recording)” note is updated or removed only after this checklist passes.
