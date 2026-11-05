import SwiftUI

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chips

struct Chip: View {
    let text: String
    var isSelected: Bool = false
    var tint: Color = Theme.accent
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? tint.opacity(0.16) : Theme.card,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isSelected ? tint.opacity(0.45) : Theme.hairline, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? tint : Theme.secondaryText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buttons

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnabled ? tint : Theme.cardMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(isEnabled ? Color.white : Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    let systemName: String
    var tint: Color = Theme.ink
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badges

struct LevelBadge: View {
    let level: JLPTLevel?

    var body: some View {
        Text(level?.label ?? "—")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.levelColor(level).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Theme.levelColor(level))
    }
}

struct FamiliarityBadge: View {
    let level: Int
    var compact: Bool = false

    var body: some View {
        Text(SpacedRepetition.familiarityTitle(level))
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.familiarityColor(level).opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.familiarityColor(level))
    }
}

struct TagLabel: View {
    let text: String
    var tint: Color = Theme.secondaryText

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.10), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Stats

struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var size: CGFloat = 76
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)
        }
        .frame(width: size, height: size)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 24)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

// MARK: - Toast

struct ToastModifier: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let text {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.ink.opacity(0.92), in: Capsule())
                    .foregroundStyle(Theme.paper)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.easeOut(duration: 0.2)) { self.text = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: text)
    }
}

extension View {
    func toast(_ text: Binding<String?>) -> some View {
        modifier(ToastModifier(text: text))
    }
}

// MARK: - Flow layout for tokens

/// Wraps tappable tokens onto as many lines as needed.
struct TokenFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Heatmap

struct ActivityHeatmap: View {
    let activities: [DayActivity]
    let goalMinutes: Double

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 5), count: 10)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(activities, id: \.dayKey) { day in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color(for: day))
                    .frame(height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: day.minutes == 0 ? 1 : 0)
                    )
            }
        }
    }

    private func color(for day: DayActivity) -> Color {
        guard goalMinutes > 0 else { return Theme.cardMuted }
        let ratio = day.minutes / goalMinutes
        switch ratio {
        case 0: return Theme.cardMuted
        case ..<0.34: return Theme.accent.opacity(0.22)
        case ..<0.67: return Theme.accent.opacity(0.45)
        case ..<1.0: return Theme.accent.opacity(0.70)
        default: return Theme.accent
        }
    }
}
