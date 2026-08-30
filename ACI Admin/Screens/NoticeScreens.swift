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
        AdShell {
            AdTitle("Notices", sub: "One-off notices to the whole congregation. Recurring sends live on their own tab.")

            AdButton(label: "New notification", icon: "plus", full: true) {
                onCompose(nil)
            }
            .padding(.horizontal, 20)

            ForEach(groups, id: \.0) { status, label in
                let rows = store.notices.filter { $0.status == status }
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
                    if let opens = n.opens {
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
    @State private var deliverLater = false
    @State private var dateOffset = 1
    @State private var time = "6:00 am"

    init(editing: Notice?) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _message = State(initialValue: editing?.message ?? "")
        _sender = State(initialValue: editing?.sender ?? AdminUser.current.church)
    }

    private var ready: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !message.trimmingCharacters(in: .whitespaces).isEmpty
            && !sender.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var scheduleLabel: String {
        deliverLater
            ? "\(AdminDates.relative(dateOffset, long: true)) at \(time)"
            : "Immediately, as soon as you send"
    }

    var body: some View {
        AdShell {
            AdTitle(
                Text("\(editing == nil ? "Write the " : "Edit the ")\(Text("notice.").italic().foregroundStyle(c.accent))"),
                sub: "Members receive this as a push notification and it appears in their in-app inbox."
            )

            AdField(label: "Title", text: $title, placeholder: "Baptism service this Sunday", chars: 65)
            AdField(label: "Message", text: $message,
                    placeholder: "What members need to know, in plain words.", rows: 5, chars: 280)
            AdField(label: "Sender", text: $sender, placeholder: AdminUser.current.church,
                    hint: "Shown above the message so members know who it came from.")

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
                    ForEach(0..<7, id: \.self) { off in
                        AdPill(label: AdminDates.relative(off), on: dateOffset == off) {
                            dateOffset = off
                        }
                    }
                }
                .padding(.horizontal, 20)

                AdEyebrow("At")
                FlowLayout(spacing: 6) {
                    ForEach(SampleData.times, id: \.self) { tm in
                        AdPill(label: tm, on: time == tm) { time = tm }
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

            AdEyebrow("How members see it")
            preview
                .padding(.horizontal, 20)

            AdHintRow(icon: "globe",
                      text: "French and Spanish drafts will appear in Review before members see them.")

            if !ready {
                Text("Add a title, message and sender to send this.")
                    .font(AdFont.sans(12))
                    .foregroundStyle(c.fgMuted)
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            }

            HStack(spacing: 8) {
                AdButton(label: "Save draft", variant: .secondary, disabled: !ready) {
                    finish("Draft saved")
                }
                AdButton(
                    label: deliverLater ? "Schedule it" : "Send now",
                    icon: deliverLater ? "clock" : "paperplane",
                    full: true, disabled: !ready
                ) {
                    finish(deliverLater ? "Scheduled · \(scheduleLabel)" : "Notification sent")
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: editing == nil ? "New notification" : "Edit notification") {
                AdTopBarAction(label: deliverLater ? "Schedule" : "Send", enabled: ready) {
                    finish(deliverLater ? "Scheduled · \(scheduleLabel)" : "Notification sent")
                }
            }
        }
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
                    Text(deliverLater ? time.replacingOccurrences(of: " ", with: "") : "now")
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

    private func finish(_ toast: String) {
        store.flash(toast)
        dismiss()
    }
}
