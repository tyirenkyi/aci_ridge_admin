//
//  HomeScreen.swift
//  ACI Admin
//
//  "Today" — needs attention, today's outbound queue, manage shortcuts.
//  Ported from AdHome in admin-screens-a.jsx.
//

import SwiftUI

struct AdHomeView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store
    @Environment(AdminSession.self) private var session

    let onReview: (Language) -> Void
    let onCompose: () -> Void
    let onQueue: () -> Void
    let onRecurring: () -> Void
    let onEvents: () -> Void

    private func loadDashboard() async { await store.loadAll() }

    private var pendingToday: Int {
        store.queue.filter { $0.state == .pending }.count
    }

    var body: some View {
        AdShell(onRefresh: { await store.loadAll(force: true) }) {
            header

            AdTitle(
                "Needs your ", accent: "attention.", accentColor: c.accent,
                sub: "\(AdminDates.long(AdminDates.today)) · \(pendingToday) notice\(pendingToday == 1 ? "" : "s") still to go out today."
            )

            AdEyebrow("Translation review")
            HStack(spacing: 10) {
                ForEach(Language.all) { lang in
                    counter(lang)
                }
            }
            .padding(.horizontal, 20)

            if store.pendingTotal > 0 {
                Text("Days you reject fall back to English — members never see a gap.")
                    .font(AdFont.sans(12))
                    .lineSpacing(2.5)
                    .foregroundStyle(c.fgMuted)
                    .padding(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
            }

            AdEyebrow(text: "Going out today") {
                AdLinkButton(label: "All notices", action: onQueue)
            }
            if store.noticesState.isInitialLoad || store.rulesState.isInitialLoad {
                AdLoadingState()
            } else if store.queue.isEmpty {
                AdEmptyState(icon: "checkmark.circle",
                             title: "Nothing scheduled for today",
                             message: "Recurring notices and anything you schedule will appear here.")
            } else {
                AdCard(flush: true) {
                    ForEach(Array(store.queue.enumerated()), id: \.element.id) { i, q in
                        queueRow(q, first: i == 0)
                    }
                }
                .padding(.horizontal, 20)
            }

            AdEyebrow("Manage")
            VStack(spacing: 8) {
                shortcut(
                    icon: "repeat", label: "Recurring notifications",
                    meta: recurringMeta, action: onRecurring
                )
                shortcut(
                    icon: "calendar", label: "Upcoming events",
                    meta: eventsMeta, action: onEvents
                )
            }
            .padding(.horizontal, 20)
        }
        .task { await loadDashboard() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            // /api/me answers with an address and a role, so that is what we show.
            Text(session.profile?.initials ?? "—")
                .font(AdFont.sans(13, weight: .bold))
                .foregroundStyle(c.onAccent)
                .frame(width: 38, height: 38)
                .background(c.accent, in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 1) {
                Text(session.profile?.email ?? "Signed in")
                    .font(AdFont.sans(14, weight: .semibold))
                    .foregroundStyle(c.fg)
                    .lineLimit(1)
                Text(session.profile?.roleLabel ?? "")
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.fgMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AdButton(label: "New", icon: "plus", variant: .secondary, small: true, action: onCompose)
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
    }

    // MARK: Translation counters

    private func counter(_ lang: Language) -> some View {
        let n = store.pendingCount(lang)
        let clear = n == 0
        return Button {
            onReview(lang)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text(lang.code)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(c.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(c.border))
                    Text(lang.native)
                        .font(AdFont.sans(12))
                        .foregroundStyle(c.fgMuted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(n)")
                        .font(AdFont.display(40))
                        .monospacedDigit()
                        .foregroundStyle(clear ? c.fgMuted : c.fg)
                    Text(clear ? "all clear" : "awaiting\nreview")
                        .font(AdFont.sans(12.5))
                        .lineSpacing(1)
                        .foregroundStyle(c.fgMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 15, bottom: 13, trailing: 15))
            .background(c.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(clear ? c.cardEdge : c.glowSoft))
        }
        .buttonStyle(.plain)
    }

    // MARK: Queue rows

    private func queueRow(_ q: QueueItem, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(q.time)
                .font(AdFont.sans(12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(q.state == .sent ? c.fgMuted : c.accent)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(q.title)
                    .font(AdFont.sans(14, weight: .semibold))
                    .foregroundStyle(c.fg)
                    .strikethrough(q.state == .sent, color: c.fgMuted)
                HStack(spacing: 7) {
                    if q.recurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                            .foregroundStyle(c.fgMuted)
                    }
                    Text(q.sender)
                        .font(AdFont.sans(11.5))
                        .foregroundStyle(c.fgMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AdChip(status: q.state == .sent ? .sent : .queued)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .opacity(q.state == .sent ? 0.6 : 1)
        .overlay(alignment: .top) {
            if !first { c.cardEdge.frame(height: 1) }
        }
    }

    // MARK: Shortcuts

    private var recurringMeta: String {
        let active = store.recurring.filter(\.active).count
        let skips = store.recurring.reduce(0) { $0 + $1.upcomingSkips.count }
        return "\(active) active · \(skips) skipped date\(skips == 1 ? "" : "s")"
    }

    private var eventsMeta: String {
        let published = store.events.filter { $0.status == .published }.count
        let drafts = store.events.filter { $0.status == .draft }.count
        return "\(published) published · \(drafts) draft"
    }

    private func shortcut(icon: String, label: String, meta: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(c.accent)
                    .frame(width: 34, height: 34)
                    .background(c.surfaceRaised, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.cardEdge))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(AdFont.sans(14, weight: .semibold))
                        .foregroundStyle(c.fg)
                    Text(meta)
                        .font(AdFont.sans(11.5))
                        .foregroundStyle(c.fgMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.fgMuted)
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
            .background(c.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.cardEdge))
        }
        .buttonStyle(.plain)
    }
}
