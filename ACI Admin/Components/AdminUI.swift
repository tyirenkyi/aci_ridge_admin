//
//  AdminUI.swift
//  ACI Admin
//
//  Atoms for the admin console, ported from admin-ui.jsx.
//  Sans for nearly everything; serif reserved for screen titles
//  and standalone numerals.
//

import SwiftUI

// MARK: - Shell

/// Scrollable screen container on the Sanctum background.
struct AdShell<Content: View>: View {
    @Environment(\.palette) private var c
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(c.bg.ignoresSafeArea())
        .foregroundStyle(c.fg)
    }
}

// MARK: - Top bar (pushed screens)

struct AdTopBar<Trailing: View>: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.fg)
                    .frame(width: 34, height: 34)
                    .background(c.surfaceRaised, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.cardEdge))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(title)
                .font(AdFont.sans(13, weight: .semibold))
                .foregroundStyle(c.fgSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            c.topBarBg
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { c.cardEdge.frame(height: 1) }
    }
}

extension AdTopBar where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Text-only trailing action for the top bar ("Send", "Save", "Publish").
struct AdTopBarAction: View {
    @Environment(\.palette) private var c
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AdFont.sans(14, weight: .bold))
                .foregroundStyle(enabled ? c.accent : c.fgMuted)
                .opacity(enabled ? 1 : 0.5)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Title & eyebrow

struct AdTitle: View {
    @Environment(\.palette) private var c
    let title: Text
    var sub: String? = nil

    init(_ title: Text, sub: String? = nil) {
        self.title = title
        self.sub = sub
    }

    init(_ plain: String, sub: String? = nil) {
        self.init(Text(plain), sub: sub)
    }

    /// "Needs your *attention.*" — trailing word italic in the accent color.
    init(_ lead: String, accent: String, accentColor: Color, sub: String? = nil) {
        self.init(
            Text("\(lead)\(Text(accent).italic().foregroundStyle(accentColor))"),
            sub: sub
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(AdFont.display(34))
                .lineSpacing(1)
                .foregroundStyle(c.fg)
            if let sub {
                Text(sub)
                    .font(AdFont.sans(13.5))
                    .lineSpacing(3)
                    .foregroundStyle(c.fgMuted)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 14, trailing: 20))
    }
}

struct AdEyebrow<Right: View>: View {
    @Environment(\.palette) private var c
    let text: String
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text.uppercased())
                .font(AdFont.label())
                .tracking(2)
                .foregroundStyle(c.fgMuted)
            Spacer(minLength: 0)
            right
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
    }
}

extension AdEyebrow where Right == EmptyView {
    init(_ text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// Small accent-colored text button used in eyebrow right slots.
struct AdLinkButton: View {
    @Environment(\.palette) private var c
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AdFont.sans(12, weight: .semibold))
                .foregroundStyle(c.accent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card

struct AdCard<Content: View>: View {
    @Environment(\.palette) private var c
    var flush: Bool = false
    var opacity: Double = 1
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(flush ? 0 : 14)
        .background(c.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.cardEdge))
        .opacity(opacity)
    }
}

// MARK: - Status chip

enum ChipStatus: String {
    case sent, scheduled, draft, pending, approved, rejected, published, active, paused, skipped, queued

    var label: String {
        switch self {
        case .sent: "Sent"
        case .scheduled: "Scheduled"
        case .draft: "Draft"
        case .pending: "Pending"
        case .approved: "Approved"
        case .rejected: "English"
        case .published: "Published"
        case .active: "On"
        case .paused: "Paused"
        case .skipped: "Skipped"
        case .queued: "Queued"
        }
    }

    enum Tone { case gold, green, red, muted, outline }

    var tone: Tone {
        switch self {
        case .sent: .muted
        case .scheduled, .pending, .queued: .gold
        case .draft, .paused: .outline
        case .approved, .published, .active: .green
        case .rejected, .skipped: .red
        }
    }
}

extension ChipStatus {
    init(_ s: NoticeStatus) { self = ChipStatus(rawValue: s.rawValue) ?? .draft }
    init(_ s: EventStatus) { self = ChipStatus(rawValue: s.rawValue) ?? .draft }
    init(_ s: ReviewStatus) { self = ChipStatus(rawValue: s.rawValue) ?? .pending }
}

struct AdChip: View {
    @Environment(\.palette) private var c
    let status: ChipStatus
    var small: Bool = true

    var body: some View {
        let (bg, fg, edge): (Color, Color, Color) = {
            switch status.tone {
            case .gold: (c.glowSoft, c.goldFg, .clear)
            case .green: (c.greenBg, c.greenFg, .clear)
            case .red: (c.redBg, c.destructive, .clear)
            case .muted: (c.surfaceRaised, c.fgMuted, .clear)
            case .outline: (.clear, c.fgMuted, c.border)
            }
        }()

        Text(status.label.uppercased())
            .font(AdFont.label(small ? 9.5 : 10.5))
            .tracking(1.1)
            .lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, small ? 7 : 9)
            .padding(.vertical, small ? 3 : 4)
            .background(bg, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(edge))
            .fixedSize()
    }
}

// MARK: - Form field

struct AdField: View {
    @Environment(\.palette) private var c
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String? = nil
    var rows: Int? = nil
    var chars: Int? = nil

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label.uppercased())
                    .font(AdFont.label())
                    .tracking(1.7)
                    .foregroundStyle(focused ? c.accent : c.fgMuted)
                Spacer(minLength: 0)
                if let chars {
                    Text("\(text.count)/\(chars)")
                        .font(AdFont.sans(11))
                        .monospacedDigit()
                        .foregroundStyle(c.fgMuted)
                }
            }

            Group {
                if let rows {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(rows...max(rows, 12))
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(AdFont.sans(15))
            .foregroundStyle(c.fg)
            .tint(c.accent)
            .focused($focused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(c.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? c.accent : c.cardEdge))

            if let hint {
                Text(hint)
                    .font(AdFont.sans(11.5))
                    .lineSpacing(2)
                    .foregroundStyle(c.fgMuted)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 14, trailing: 20))
    }
}

// MARK: - Buttons

enum AdButtonVariant { case primary, gold, secondary, ghost, danger }

struct AdButton: View {
    @Environment(\.palette) private var c
    let label: String
    var icon: String? = nil
    var variant: AdButtonVariant = .primary
    var full: Bool = false
    var small: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        let (bg, fg, edge): (Color, Color, Color) = {
            if disabled { return (c.surfaceRaised, c.fgMuted, c.cardEdge) }
            switch variant {
            case .primary: return (c.accent, c.onAccent, .clear)
            case .gold: return (c.glow, c.onGlow, .clear)
            case .secondary: return (c.surfaceRaised, c.fg, c.cardEdge)
            case .ghost: return (.clear, c.fg, c.border)
            case .danger: return (.clear, c.destructive, c.dangerEdge)
            }
        }()

        Button(action: action) {
            HStack(spacing: 8) {
                if let icon, !disabled {
                    Image(systemName: icon)
                        .font(.system(size: small ? 13 : 15, weight: .semibold))
                }
                Text(label)
                    .font(AdFont.sans(small ? 13 : 14.5, weight: .semibold))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: full ? .infinity : nil)
            .frame(minHeight: small ? 38 : 46)
            .padding(.horizontal, small ? 14 : 20)
            .background(bg, in: .rect(cornerRadius: small ? 10 : 12))
            .overlay(RoundedRectangle(cornerRadius: small ? 10 : 12).strokeBorder(edge))
            .opacity(disabled ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Toggle

struct AdToggle: View {
    @Environment(\.palette) private var c
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            HStack {
                if isOn { Spacer(minLength: 0) }
                Circle()
                    .fill(isOn ? c.onAccent : c.fgMuted)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                if !isOn { Spacer(minLength: 0) }
            }
            .padding(2)
            .frame(width: 46, height: 28)
            .background(isOn ? c.accent : c.surfaceRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? .clear : c.border))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented control

struct AdSegmentOption: Identifiable {
    let label: String
    let value: String
    var badge: Int = 0
    var id: String { value }
}

struct AdSegmented: View {
    @Environment(\.palette) private var c
    let options: [AdSegmentOption]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { o in
                let on = o.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = o.value }
                } label: {
                    HStack(spacing: 7) {
                        Text(o.label)
                            .font(AdFont.sans(13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? c.fg : c.fgMuted)
                        if o.badge > 0 {
                            AdBadge(count: o.badge)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(on ? c.card : .clear, in: .rect(cornerRadius: 9))
                    .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 1.5, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(c.surfaceRaised, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.cardEdge))
    }
}

// MARK: - Badge

struct AdBadge: View {
    @Environment(\.palette) private var c
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(c.onGlow)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(c.glow, in: .capsule)
    }
}

// MARK: - Selection pill

/// Rounded selectable pill used for dates, times and weekdays.
struct AdPill: View {
    @Environment(\.palette) private var c
    let label: String
    let on: Bool
    var wide: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AdFont.sans(13, weight: on ? .bold : .regular))
                .foregroundStyle(on ? c.onAccent : c.fgSecondary)
                .lineLimit(1)
                .frame(maxWidth: wide ? .infinity : nil, minHeight: 38)
                .padding(.horizontal, 12)
                .background(on ? c.accent : .clear, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? .clear : c.border))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow layout (wrapping pill rows)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Hint row (icon + muted copy)

struct AdHintRow: View {
    @Environment(\.palette) private var c
    let icon: String
    let text: String
    var iconColor: Color? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor ?? c.fgMuted)
                .frame(width: 16)
                .padding(.top, 1)
            Text(text)
                .font(AdFont.sans(12))
                .lineSpacing(2.5)
                .foregroundStyle(c.fgMuted)
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
    }
}

// MARK: - Tab bar

enum AdminTab: String, CaseIterable, Identifiable {
    case today, notices, recurring, events, review
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .notices: "Notices"
        case .recurring: "Recurring"
        case .events: "Events"
        case .review: "Review"
        }
    }

    var icon: String {
        switch self {
        case .today: "sparkle"
        case .notices: "bell"
        case .recurring: "repeat"
        case .events: "calendar"
        case .review: "globe"
        }
    }
}

struct AdTabBar: View {
    @Environment(\.palette) private var c
    @Binding var selection: AdminTab
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AdminTab.allCases) { tab in
                let on = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(on ? c.accent : c.fgMuted)
                            .frame(height: 24)
                            .overlay(alignment: .topTrailing) {
                                if tab == .review, badge > 0 {
                                    Text("\(badge)")
                                        .font(.system(size: 9.5, weight: .heavy))
                                        .monospacedDigit()
                                        .foregroundStyle(c.onGlow)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(c.glow, in: .capsule)
                                        .offset(x: 10, y: -4)
                                }
                            }
                        Text(tab.label)
                            .font(AdFont.sans(10, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? c.fg : c.fgMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .background {
            c.barBg
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
    }
}

// MARK: - Bottom sheet (confirmations)

struct AdSheet<Body_: View, Actions: View>: ViewModifier {
    @Environment(\.palette) private var c
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder var message: Body_
    @ViewBuilder var actions: Actions

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack(alignment: .bottom) {
                    if isPresented {
                        Color(rgba: 4, 3, 16, 0.55)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                            }

                        VStack(alignment: .leading, spacing: 0) {
                            Capsule()
                                .fill(c.border)
                                .frame(width: 38, height: 4)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 18)

                            Text(title)
                                .font(AdFont.display(25))
                                .foregroundStyle(c.fg)

                            message
                                .font(AdFont.sans(13.5))
                                .lineSpacing(3)
                                .foregroundStyle(c.fgSecondary)
                                .padding(.top, 10)

                            VStack(spacing: 8) {
                                actions
                            }
                            .padding(.top, 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 10, leading: 20, bottom: 14, trailing: 20))
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                                .fill(c.surface)
                                .overlay(
                                    UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                                        .strokeBorder(c.cardEdge)
                                )
                                .ignoresSafeArea(edges: .bottom)
                                .shadow(color: .black.opacity(0.45), radius: 30, y: -10)
                        }
                        .transition(.move(edge: .bottom))
                    }
                }
                .animation(.spring(duration: 0.35), value: isPresented)
            }
    }
}

extension View {
    func adSheet<B: View, A: View>(
        isPresented: Binding<Bool>,
        title: String,
        @ViewBuilder message: () -> B,
        @ViewBuilder actions: () -> A
    ) -> some View {
        modifier(AdSheet(isPresented: isPresented, title: title, message: message, actions: actions))
    }
}

// MARK: - Toast

struct AdToast: View {
    @Environment(\.palette) private var c
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(c.glow)
            Text(message)
                .font(AdFont.sans(13.5, weight: .semibold))
                .foregroundStyle(c.toastFg)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
        .background(c.toastBg, in: .rect(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(c.glowSoft))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
        .padding(.horizontal, 20)
    }
}
