import SwiftUI

/// PS4 DualShock 4 手柄可视化组件。
/// 用 SF Symbol + 文字标签展示按键布局（无 emoji）。
struct ControllerVisual: View {
    let selectedInput: ControllerInput?
    let onSelect: (ControllerInput) -> Void

    @ObservedObject private var i18n = Localization.shared

    private let buttonSize: CGFloat = 44
    private let stickSize: CGFloat = 60

    var body: some View {
        ZStack {
            // 手柄主体背景
            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 80, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .frame(width: 520, height: 360)

            // 左握把
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .frame(width: 130, height: 180)
                .offset(x: -190, y: 60)

            // 右握把
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .frame(width: 130, height: 180)
                .offset(x: 190, y: 60)

            VStack(spacing: 16) {
                // 顶部：Share / PS / Options
                HStack {
                    button(.share, label: "Share", systemImage: "square.and.arrow.up")
                    Spacer()
                    button(.ps, label: "PS", systemImage: "power")
                    Spacer()
                    button(.options, label: "Options", systemImage: "ellipsis")
                }
                .padding(.horizontal, 80)

                // 中部：左右摇杆 + XYAB
                HStack(alignment: .center, spacing: 28) {
                    // 左：D-pad + 左摇杆（L3）
                    VStack(spacing: 6) {
                        dpad
                            .frame(width: 110, height: 110)
                        stickButton(.l3, label: "L3", help: i18n.t("visual.l3.help"))
                    }

                    // 中：触摸板
                    Button(action: { onSelect(.touchpadButton) }) {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(buttonColor(for: .touchpadButton))
                                .frame(width: 100, height: 64)
                                .overlay(
                                    Image(systemName: "rectangle.compress.vertical")
                                        .imageScale(.large)
                                )
                            Text(i18n.t("visual.touchpad"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // 右：XYAB + 右摇杆（R3）
                    VStack(spacing: 6) {
                        xyab
                            .frame(width: 110, height: 110)
                        stickButton(.r3, label: "R3", help: i18n.t("visual.r3.help"))
                    }
                }

                // 底部：L1/L2/R1/R2
                HStack {
                    triggerButton(.l1, label: "L1", systemImage: "l.square")
                    triggerButton(.leftTriggerAxis, label: "L2", systemImage: "l.square.fill")
                    Spacer()
                    triggerButton(.r1, label: "R1", systemImage: "r.square")
                    triggerButton(.rightTriggerAxis, label: "R2", systemImage: "r.square.fill")
                }
                .padding(.horizontal, 80)
            }
            .padding(.vertical, 30)
        }
    }

    // MARK: - D-Pad

    private var dpad: some View {
        ZStack {
            // 上下左右
            button(.dpadUp, label: i18n.t("visual.up"), systemImage: "chevron.up")
                .offset(y: -36)
            button(.dpadDown, label: i18n.t("visual.down"), systemImage: "chevron.down")
                .offset(y: 36)
            button(.dpadLeft, label: i18n.t("visual.left"), systemImage: "chevron.left")
                .offset(x: -36)
            button(.dpadRight, label: i18n.t("visual.right"), systemImage: "chevron.right")
                .offset(x: 36)
        }
    }

    // MARK: - XYAB

    private var xyab: some View {
        ZStack {
            // 上 = △, 右 = ○, 下 = ×, 左 = □
            button(.triangle, label: "△", systemImage: "triangle.fill")
                .offset(y: -36)
            button(.circle, label: "○", systemImage: "circle.fill")
                .offset(x: 36)
            button(.cross, label: "×", systemImage: "xmark")
                .offset(y: 36)
            button(.square, label: "□", systemImage: "square.fill")
                .offset(x: -36)
        }
    }

    // MARK: - 通用按键按钮

    private func button(_ input: ControllerInput, label: String, systemImage: String) -> some View {
        Button(action: { onSelect(input) }) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 50, height: 50)
            .background(buttonColor(for: input))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: selectedInput == input ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    /// 摇杆按下（L3/R3）。之前手柄图上完全没画摇杆，所以这两个键在编辑器里根本点不到。
    private func stickButton(_ input: ControllerInput, label: String, help: String) -> some View {
        Button(action: { onSelect(input) }) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.caption2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(buttonColor(for: input))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.6),
                                  lineWidth: selectedInput == input ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func triggerButton(_ input: ControllerInput, label: String, systemImage: String) -> some View {
        Button(action: { onSelect(input) }) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 56, height: 30)
            .background(buttonColor(for: input))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: selectedInput == input ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    private func buttonColor(for input: ControllerInput) -> Color {
        if selectedInput == input {
            return Color.accentColor.opacity(0.3)
        }
        return Color.secondary.opacity(0.15)
    }
}
