import SwiftUI

extension SSHColorTag {
    var color: Color {
        switch self {
        case .none: .secondary.opacity(0.35)
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

extension SSHColorTag {
    var chineseLabel: String {
        switch self {
        case .none: return "无标签"
        case .gray: return "灰色"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        }
    }

    var emoji: String {
        switch self {
        case .none: return "⚪️"
        case .gray: return "🔘"
        case .red: return "🔴"
        case .orange: return "🟠"
        case .yellow: return "🟡"
        case .green: return "🟢"
        case .blue: return "🔵"
        case .purple: return "🟣"
        }
    }
}

struct ColorTagMenu: View {
    let selection: SSHColorTag
    let onSelect: (SSHColorTag) -> Void

    var body: some View {
        ForEach(SSHColorTag.allCases) { tag in
            Button {
                onSelect(tag)
            } label: {
                HStack {
                    if selection == tag {
                        Image(systemName: "checkmark")
                    }
                    if tag == .none {
                        Image(systemName: "slash.circle")
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(tag.color)
                    }
                    Text(LocalizedStringKey(tag.chineseLabel))
                }
            }
        }
    }
}

struct ColorTagPicker: View {
    @Binding var selection: SSHColorTag

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SSHColorTag.allCases) { tag in
                Button {
                    selection = tag
                } label: {
                    ZStack {
                        Circle()
                            .fill(tag == .none ? Color.secondary.opacity(0.12) : tag.color)
                        if tag == .none {
                            Image(systemName: "slash")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if selection == tag {
                            Circle()
                                .stroke(.primary.opacity(0.8), lineWidth: 2)
                                .padding(-3)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tag.label)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 18)
    }
}
