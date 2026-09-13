//
//  NoticeScreens.swift
//  ACI Admin
//
//  One-off notices list and the compose/edit screen.
//  Ported from admin-screens-b.jsx.
//

import SwiftUI

// MARK: - Notices list

struct AdNoticesView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    let onCompose: (Notice?) -> Void

    private let groups: [(NoticeStatus, String)] = [
        (.scheduled, "Scheduled"),
        (.draft, "Drafts"),
        (.sent, "Sent"),
    ]

    var body: some View {
        AdShell(onRefresh: { await store.loadNotices(force: true) }) {
            AdTitle("Notices", sub: "One-off notices to the whole congregation. Recurring sends live on their own tab.")

            AdButton(label: "New notification", icon: "plus", full: true) {
                onCompose(nil)
            }
            .padding(.horizontal, 20)

            AdLoadState(store.noticesState, retry: { await store.loadNotices(force: true) }) { notices in
                if notices.isEmpty {
                    AdEmptyState(
                        icon: "bell",
                        title: "No notices yet",
                        message: "Anything you write here reaches every member as a push notification.",
                        actionLabel: "Write the first one"
                    ) { onCompose(nil) }
                } else {
                    ForEach(groups, id: \.0) { status, label in
                        let rows = notices.filter { $0.status == status }
                        if !rows.isEmpty {
                            AdEyebrow("\(label) · \(rows.count)")
                            AdCard(flush: true) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { i, n in
                                    noticeRow(n, first: i == 0)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
        .task { await store.loadNotices() }
    }

    private func noticeRow(_ n: Notice, first: Bool) -> some View {
        Button {
            onCompose(n)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(n.title)
                            .font(AdFont.sans(14.5, weight: .semibold))
                            .foregroundStyle(c.fg)
                            .multilineTextAlignment(.leading)
                        Text(n.message)
                            .font(AdFont.sans(12.5))
                            .lineSpacing(2.5)
                            .foregroundStyle(c.fgSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AdChip(status: ChipStatus(n.status))
                }

                HStack(spacing: 8) {
                    Text(n.sender)
                        .font(AdFont.sans(11.5, weight: .semibold))
                        .foregroundStyle(c.accent)
                    Text("·").opacity(0.5)
                    Text(n.when)
                    if let opens = n.opensLabel {
                        Text("·").opacity(0.5)
                        Text(opens)
                    }
                }
                .font(AdFont.sans(11.5))
                .foregroundStyle(c.fgMuted)
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
            .contentShape(.rect)
            .overlay(alignment: .top) {
                if !first { c.cardEdge.frame(height: 1) }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compose / edit a notification

struct AdComposeNoticeView: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @Environment(AdminStore.self) private var store

    let editing: Notice?

    @State private var title: String
    @State private var message: String
    @State private var sender: String
    @State private var deliverLater: Bool
    @State private var dateOffset: Int
    @State private var time: TimeOfDay
    @State private var submitting = false
    /// Set once a create succeeds, so a failed send is retried against the notice we
    /// already made rather than creating a second one.
    @State private var noticeID: String?

    init(editing: Notice?) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _message = State(initialValue: editing?.message ?? "")
        _sender = State(initialValue: editing?.sender.isEmpty == false ? editing!.sender : APIConfig.churchName)
        _noticeID = State(initialValue: editing?.id)

        let scheduled = editing?.scheduledAt
        _deliverLater = State(initialValue: scheduled != nil)
        _dateOffset = State(initialValue: scheduled.map { max(CalendarDay($0).offsetFromToday(), 0) } ?? 1)
        _time = State(initialValue: scheduled.map { TimeOfDay($0) } ?? AdminTimes.default)
    }

    /// A sent notice is history — the server rejects edits and deletes with a 409.
    private var isReadOnly: Bool { editing?.status == .sent }

    private var ready: Bool {
        !title.trimmed.isEmpty && !message.trimmed.isEmpty && !sender.trimmed.isEmpty
    }

    /// Scheduling into the past is a 400, so today only offers times still to come.
    private var timeOptions: [TimeOfDay] {
        guard deliverLater, dateOffset == 0 else { return AdminTimes.options }
        let now = TimeOfDay(Date())
        return AdminTimes.options.filter { $0 > now }
    }

    /// Drop "Today" once nothing is left of it.
    private var dayOffsets: [Int] {
        let now = TimeOfDay(Date())
        let todayHasTime = AdminTimes.options.contains { $0 > now }
        return Array(0..<7).filter { $0 != 0 || todayHasTime }
    }

    private var scheduledDate: Date? {
        guard deliverLater else { return nil }
        return CalendarDay.today.adding(days: dateOffset).date(at: time)
    }

    private var scheduleLabel: String {
        deliverLater
            ? "\(AdminDates.relative(dateOffset, long: true)) at \(time.display)"
            : "Immediately, as soon as you send"
    }

    private var draft: NoticeDraft {
        var draft = NoticeDraft()
        draft.title = title
        draft.message = message
        draft.sender = sender
        draft.scheduledAt = scheduledDate
        return draft
    }

    var body: some View {
        AdShell {
            AdTitle(
                Text("\(editing == nil ? "Write the " : "Edit the ")\(Text("notice.").italic().foregroundStyle(c.accent))"),
                sub: isReadOnly
                    ? "This one has already gone out, so it can't be changed."
                    : "Members receive this as a push notification and it appears in their in-app inbox."
            )

            if isReadOnly, let editing {
                AdHintRow(icon: "paperplane.fill",
                          text: "\(editing.when)\(editing.opensLabel.map { " · \($0)" } ?? "")",
                          iconColor: c.accent)
            }

            AdField(label: "Title", text: $title, placeholder: "Baptism service this Sunday",
                    chars: 65, disabled: isReadOnly)
            AdField(label: "Message", text: $message,
                    placeholder: "What members need to know, in plain words.", rows: 5, chars: 280,
                    disabled: isReadOnly)
            AdField(label: "Sender", text: $sender, placeholder: APIConfig.churchName,
                    hint: "Shown above the message so members know who it came from.",
                    disabled: isReadOnly)

            if !isReadOnly {
                deliverySection
            }

            AdEyebrow("How members see it")
            preview
                .padding(.horizontal, 20)

            AdHintRow(icon: "globe",
                      text: "French and Spanish drafts will appear in Review before members see them.")

            if !isReadOnly {
                if !ready {
                    Text("Add a title, message and sender to send this.")
                        .font(AdFont.sans(12))
                        .foregroundStyle(c.fgMuted)
                        .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
                }

                HStack(spacing: 8) {
                    AdButton(label: "Save draft", variant: .secondary,
                             disabled: !ready || submitting) {
                        submit(.draft)
                    }
                    AdButton(
                        label: deliverLater ? "Schedule it" : "Send now",
                        icon: deliverLater ? "clock" : "paperplane",
                        full: true, disabled: !ready || submitting, loading: submitting
                    ) {
                        submit(deliverLater ? .schedule : .sendNow)
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: topBarTitle) {
                if !isReadOnly {
                    AdTopBarAction(label: deliverLater ? "Schedule" : "Send",
                                   enabled: ready && !submitting, loading: submitting) {
                        submit(deliverLater ? .schedule : .sendNow)
                    }
                }
            }
        }
        .onChange(of: dateOffset) { _, _ in snapTimeIntoRange() }
        .onChange(of: deliverLater) { _, _ in snapTimeIntoRange() }
    }

    private var topBarTitle: String {
        if isReadOnly { return "Sent notification" }
        return editing == nil ? "New notification" : "Edit notification"
    }

    @ViewBuilder
    private var deliverySection: some View {
        AdEyebrow("Delivery")
        AdSegmented(
            options: [
                AdSegmentOption(label: "Immediately", value: "now"),
                AdSegmentOption(label: "Schedule", value: "later"),
            ],
            selection: Binding(
                get: { deliverLater ? "later" : "now" },
                set: { deliverLater = $0 == "later" }
            )
        )
        .padding(.horizontal, 20)

        if deliverLater {
            AdEyebrow("On")
            FlowLayout(spacing: 6) {
                ForEach(dayOffsets, id: \.self) { off in
                    AdPill(label: AdminDates.relative(off), on: dateOffset == off) {
                        dateOffset = off
                    }
                }
            }
            .padding(.horizontal, 20)

            AdEyebrow("At")
            FlowLayout(spacing: 6) {
                ForEach(timeOptions, id: \.self) { option in
                    AdPill(label: option.display, on: time == option) { time = option }
                }
            }
            .padding(.horizontal, 20)
        }

        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 13))
                .foregroundStyle(c.accent)
            Text(scheduleLabel)
                .font(AdFont.sans(12.5))
                .foregroundStyle(c.fgSecondary)
        }
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
    }

    /// Keeps the chosen time inside what the chosen day still allows.
    private func snapTimeIntoRange() {
        guard let first = timeOptions.first else { return }
        if !timeOptions.contains(time) { time = first }
    }

    // MARK: Writing

    private enum Intent { case draft, schedule, sendNow }

    private func submit(_ intent: Intent) {
        guard !submitting else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do throws(APIError) {
                switch intent {
                case .draft:
                    _ = try await save(status: .draft)
                    finish("Draft saved")
                case .schedule:
                    _ = try await save(status: .scheduled)
                    finish("Scheduled · \(scheduleLabel)")
                case .sendNow:
                    try await sendNow()
                }
            } catch {
                store.flashError(error)
            }
        }
    }

    private func save(status: NoticeStatus) async throws(APIError) -> Notice {
        if let id = noticeID {
            return try await store.updateNotice(id, to: draft, status: status)
        }
        let created = try await store.createNotice(draft, scheduled: status == .scheduled)
        noticeID = created.id
        return created
    }

    /// There is no create-and-send endpoint, so a fresh notice is two calls. If the
    /// second fails the draft still exists — stay on the screen, now editing it, so a
    /// retry doesn't produce a duplicate.
    private func sendNow() async throws(APIError) {
        let wasNew = noticeID == nil
        let notice = try await save(status: .draft)
        do throws(APIError) {
            _ = try await store.sendNotice(notice.id)
            finish("Notification sent")
        } catch {
            if wasNew {
                store.flash("Saved as a draft, but sending failed — \(error.message)", kind: .error)
            } else {
                store.flashError(error)
            }
        }
    }

    private func finish(_ toast: String) {
        store.flash(toast)
        dismiss()
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("✦")
                .font(AdFont.serif(17))
                .foregroundStyle(c.glow)
                .frame(width: 34, height: 34)
                .background(c.accent, in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title.isEmpty ? "Notification title" : title)
                        .font(AdFont.sans(13, weight: .bold))
                        .foregroundStyle(c.fg)
                    Spacer(minLength: 0)
                    Text(deliverLater ? time.display.replacingOccurrences(of: " ", with: "") : "now")
                        .font(AdFont.sans(11))
                        .foregroundStyle(c.fgMuted)
                }
                Text(message.isEmpty ? "Your message appears here." : message)
                    .font(AdFont.sans(12.5))
                    .lineSpacing(2.5)
                    .foregroundStyle(message.isEmpty ? c.fgMuted : c.fgSecondary)
                Text(sender.isEmpty ? "Sender" : sender)
                    .font(AdFont.sans(11))
                    .foregroundStyle(c.fgMuted)
                    .padding(.top, 3)
            }
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.previewBg, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(c.cardEdge))
    }

}
