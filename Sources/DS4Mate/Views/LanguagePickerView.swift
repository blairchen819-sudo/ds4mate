import SwiftUI
import AppKit

/// 首次启动的语言选择界面。
///
/// 两个语言各自用本语言显示（English / 简体中文），不做翻译——用户此刻
/// 还没选定语言，任何"翻译过的语言名"都可能让他认不出自己那一项。
struct LanguagePickerView: View {
    /// 用户点选后回调；选中即在调用方落盘，不需要再点"继续"。
    let onChoose: (AppLanguage) -> Void

    @State private var hovered: AppLanguage?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tint)
                Text("DS4Mate")
                    .font(.title2.weight(.semibold))
                Text("Choose your language · 选择界面语言")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            HStack(spacing: 16) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    languageCard(language)
                }
            }
            .padding(.horizontal, 32)

            Text("You can change this later in Settings · 之后可在「设置」里随时更改")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
                .padding(.bottom, 28)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func languageCard(_ language: AppLanguage) -> some View {
        Button {
            onChoose(language)
        } label: {
            VStack(spacing: 6) {
                Text(language.nativeName)
                    .font(.title3.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(hovered == language
                        ? Color.accentColor.opacity(0.16)
                        : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovered == language ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: hovered == language ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? language : (hovered == language ? nil : hovered)
        }
    }
}
