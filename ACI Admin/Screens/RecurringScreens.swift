//
//  RecurringScreens.swift
//  ACI Admin
//
//  Recurring notices, the rule composer, and per-rule occurrence skipping.
//  Ported from admin-screens-c.jsx and admin-screens-d.jsx.
//

import SwiftUI

// MARK: - Recurring list

struct AdRecurringView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    let onOpen: (RecurringRule) -> Void
    let onEdit: (RecurringRule?) -> Void

    var body: some View {
        AdShell(onRefresh: { await store.loadRules(force: true) }) {
            AdTitle("Recurring", sub: "Notices that send themselves on a schedule. Skip a single date without touching the rule.")

            AdButton(label: "New recurring notice", icon: "plus", variant: .secondary, full: true) {
                onEdit(nil)
            }
            .padding(.horizontal, 20)

            AdLoadState(store.rulesState, retry: { await store.loadRules(force: true) }) { rules in
                if rules.isEmpty {
                    AdEmptyState(
                        icon: "repeat",
                        title: "No recurring notices",
                        message: "These send themselves on a schedule — a daily devotion prompt, a Sunday service reminder."
                    )
                } else {
                    AdEyebrow(eyebrowText(rules))

                    VStack(spacing: 8) {
                        ForEach(rules) { rule in
                            ruleCard(rule)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { await store.loadRules() }
    }

    private func eyebrowText(_ rules: [RecurringRule]) -> String {
        let active = rules.filter(\.active).count
        // Only skips still ahead are worth counting; past ones have already happened.
        let skips = rules.reduce(0) { $0 + $1.upcomingSkips.count }
        guard skips > 0 else { return "\(active) active" }
        return "\(active) active · \(skips) date\(skips == 1 ? "" : "s") skipped"
    }

    private func ruleCard(_ rule: RecurringRule) -> some View {
        AdCard(opacity: rule.active ? 1 : 0.62) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onOpen(rule)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rule.title)
                            .font(AdFont.sans(15, weight: .semibold))
                            .foregroundStyle(c.fg)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 7) {
                            Image(systemName: "repeat")
                                .font(.system(size: 11, weight: .medium))
                            Text(rule.ruleLabel)
                        }
                        .font(AdFont.sans(12, weight: .semibold))
                        .foregroundStyle(c.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                AdToggle(isOn: Binding(
                    get: { store.rule(rule.id)?.active ?? rule.active },
                    set: { isOn in Task { await store.setRuleActive(rule.id, isOn) } }
                ))
            }

            Text(rule.message)
                .font(AdFont.sans(12.5))
                .lineSpacing(2.5)
                .foregroundStyle(c.fgSecondary)
                .lineLimit(2)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Text(rule.sender + (rule.upcomingSkips.isEmpty ? "" : " · \(rule.upcomingSkips.count) skipped"))
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !rule.upcomingSkips.isEmpty {
                    AdChip(status: .skipped)
                }

                Button {
                    onEdit(rule)
                } label: {
                    Text("Edit")
                        .font(AdFont.sans(12, weight: .semibold))
                        .foregroundStyle(c.fgSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    onOpen(rule)
                } label: {
                    HStack(spacing: 3) {
                        Text("Schedule")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(AdFont.sans(12, weight: .semibold))
                    .foregroundStyle(c.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
            .padding(.top, 11)
        }
    }
}

// MARK: - Rule composer

struct AdRecurringComposeView: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @Environment(AdminStore.self) private var store

    let editing: RecurringRule?

    @State private var title: String
    @State private var message: String
    @State private var sender: String
    @State private var kind: RecurrenceKind
    @State private var days: [Int]
    @State private var dayOfMonth: Int
    @State private var time: TimeOfDay
    @State private var submitting = false

    init(editing: RecurringRule?) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _message = State(initialValue: editing?.message ?? "")
        _sender = State(initialValue: editing?.sender.isEmpty == false ? editing!.sender : APIConfig.churchName)
        _kind = State(initialValue: editing?.kind ?? .weekly)
        _days = State(initialValue: editing?.days.isEmpty == false ? editing!.days : [0])
        _dayOfMonth = State(initialValue: editing?.dayOfMonth ?? 1)
        _time = State(initialValue: editing?.sendTime ?? AdminTimes.default)
    }

    private var draftRule: RecurringRule {
        RecurringRule(id: "draft", title: title, message: message, sender: sender,
                      kind: kind, days: days, dayOfMonth: dayOfMonth,
                      sendTime: time, active: true)
    }

    private var ruleReady: Bool { kind != .weekly || !days.isEmpty }

    private var ready: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !message.trimmingCharacters(in: .whitespaces).isEmpty
            && !sender.trimmingCharacters(in: .whitespaces).isEmpty
            && ruleReady
    }

    var body: some View {
        AdShell {
            AdTitle(
                Text("Set the \(Text("rhythm.").italic().foregroundStyle(c.accent))"),
                sub: "This notice sends itself on the schedule you set, until you switch it off."
            )

            AdField(label: "Title", text: $title, placeholder: "Tuesday evening service", chars: 65)
            AdField(label: "Message", text: $message,
                    placeholder: "The same words go out every time — keep them evergreen.", rows: 4, chars: 280)
            AdField(label: "Sender", text: $sender, placeholder: APIConfig.churchName)

            AdEyebrow("Repeats")
            AdSegmented(
                options: RecurrenceKind.allCases.map { AdSegmentOption(label: $0.label, value: $0.rawValue) },
                selection: Binding(
                    get: { kind.rawValue },
                    set: { kind = RecurrenceKind(rawValue: $0) ?? .daily }
                )
            )
            .padding(.horizontal, 20)

            if kind == .weekly {
                AdEyebrow(text: "On these days") {
                    AdLinkButton(label: days.count == 7 ? "Clear" : "Every day") {
                        days = days.count == 7 ? [] : Array(0...6)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        AdPill(label: String(AdminDates.dayShort[i].prefix(1)), on: days.contains(i), wide: true) {
                            if let j = days.firstIndex(of: i) { days.remove(at: j) }
                            else { days.append(i) }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if kind == .monthly {
                AdEyebrow("Day of the month")
                AdCard {
                    HStack(spacing: 14) {
                        AdPill(label: "−", on: false) { dayOfMonth = max(1, dayOfMonth - 1) }
                        VStack(spacing: 4) {
                            Text(AdminDates.ordinal(dayOfMonth))
                                .font(AdFont.display(34))
                                .monospacedDigit()
                                .foregroundStyle(c.fg)
                            Text("of every month")
                                .font(AdFont.sans(11.5))
                                .foregroundStyle(c.fgMuted)
                        }
                        .frame(maxWidth: .infinity)
                        AdPill(label: "+", on: false) { dayOfMonth = min(28, dayOfMonth + 1) }
                    }
                    Text("Capped at the 28th so every month has the date.")
                        .font(AdFont.sans(11.5))
                        .foregroundStyle(c.fgMuted)
                        .padding(.top, 10)
                        .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
            }

            AdEyebrow("Send at")
            FlowLayout(spacing: 6) {
                ForEach(AdminTimes.options, id: \.self) { option in
                    AdPill(label: option.display, on: time == option) { time = option }
                }
            }
            .padding(.horizontal, 20)

            AdEyebrow("The schedule")
            AdCard {
                HStack(spacing: 10) {
                    Image(systemName: "repeat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(c.accent)
                    Text(draftRule.ruleLabel)
                        .font(AdFont.sans(13.5, weight: .semibold))
                        .foregroundStyle(c.fg)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("FIRST THREE SENDS")
                        .font(AdFont.label(10))
                        .tracking(1.6)
                        .foregroundStyle(c.fgMuted)
                    if ruleReady {
                        ForEach(draftRule.occurrences(count: 3)) { o in
                            HStack(spacing: 9) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                    .foregroundStyle(c.accent)
                                Text("\(AdminDates.long(o.date))\(o.day.isToday ? " · today" : "") at \(time.display)")
                                    .font(AdFont.sans(12.5))
                                    .foregroundStyle(c.fgSecondary)
                            }
                        }
                    } else {
                        Text("Pick at least one day to see the schedule.")
                            .font(AdFont.sans(12.5))
                            .foregroundStyle(c.fgMuted)
                    }
                }
                .padding(.top, 11)
                .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                .padding(.top, 11)
            }
            .padding(.horizontal, 20)

            if !ready {
                Text(ruleReady
                     ? "Add a title, message and sender to save this."
                     : "Pick at least one day, and fill in the title, message and sender.")
                    .font(AdFont.sans(12))
                    .lineSpacing(2.5)
                    .foregroundStyle(c.fgMuted)
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            }

            HStack(spacing: 8) {
                AdButton(label: "Save paused", variant: .secondary, disabled: !ready || submitting) {
                    save(active: false, toast: "Saved — paused for now")
                }
                AdButton(label: "Save & switch on", icon: "repeat", full: true,
                         disabled: !ready || submitting, loading: submitting) {
                    save(active: true, toast: "Recurring notice switched on")
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: editing == nil ? "New recurring notice" : "Edit recurring notice") {
                AdTopBarAction(label: "Save", enabled: ready && !submitting, loading: submitting) {
                    save(active: editing?.active ?? true,
                         toast: editing == nil ? "Recurring notice switched on" : "Changes saved")
                }
            }
        }
    }

    private var draft: RuleDraft {
        var draft = RuleDraft()
        draft.title = title
        draft.message = message
        draft.sender = sender
        draft.kind = kind
        draft.days = days
        draft.dayOfMonth = dayOfMonth
        draft.sendTime = time
        return draft
    }

    private func save(active: Bool, toast: String) {
        guard !submitting else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do throws(APIError) {
                // This endpoint replaces the whole definition — it rejects a partial
                // body — so the draft always sends every field.
                _ = try await store.saveRule(draft, id: editing?.id, active: active)
                finish(toast)
            } catch {
                store.flashError(error)
            }
        }
    }

    private func finish(_ toast: String) {
        store.flash(toast)
        dismiss()
    }
}

// MARK: - Schedule (occurrences, skippable)

struct AdScheduleView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    let ruleID: RecurringRule.ID

    @State private var confirming: RuleOccurrence? = nil

    private var rule: RecurringRule? { store.rule(ruleID) }

    var body: some View {
        if let rule {
            content(rule)
                .task { await store.loadOccurrences(ruleID) }
        }
    }

    private func content(_ rule: RecurringRule) -> some View {
        AdShell {
            AdTitle(
                Text("Next \(Text("sends.").italic().foregroundStyle(c.accent))"),
                sub: rule.upcomingSkips.isEmpty
                    ? "Tap Skip on any date to hold that one send. The rule itself stays as it is."
                    : "\(rule.upcomingSkips.count) upcoming date\(rule.upcomingSkips.count == 1 ? "" : "s") skipped. The rule itself stays as it is."
            )

            AdCard {
                HStack(spacing: 10) {
                    Image(systemName: "repeat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(c.accent)
                    Text(rule.ruleLabel)
                        .font(AdFont.sans(13.5, weight: .semibold))
                        .foregroundStyle(c.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AdChip(status: rule.active ? .active : .paused)
                }
                Text(rule.message)
                    .font(AdFont.sans(12.5))
                    .lineSpacing(2.5)
                    .foregroundStyle(c.fgSecondary)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                    .padding(.top, 10)
                Text(rule.sender)
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.fgMuted)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)

            AdEyebrow("Upcoming occurrences")
            AdLoadState(
                store.occurrencesState[ruleID] ?? .loading,
                retry: { await store.loadOccurrences(ruleID, force: true) }
            ) { occurrences in
                AdCard(flush: true) {
                    ForEach(Array(occurrences.enumerated()), id: \.element.id) { i, o in
                        occurrenceRow(rule, o, first: i == 0)
                    }
                }
                .padding(.horizontal, 20)
            }

            AdHintRow(icon: "sparkle",
                      text: "Skipping affects one date only. To stop the notice entirely, switch it off on the Recurring tab.")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: rule.title)
        }
        .adSheet(
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            title: confirming.map { "Skip \(AdminDates.long($0.day.date()))?" } ?? ""
        ) {
            if let o = confirming {
                Text("\(Text(rule.title).fontWeight(.semibold).foregroundStyle(c.fg)) will not send\(o.isToday ? " today" : " on \(AdminDates.short(o.day.date()))") at \(o.time.display). Every other date on this schedule is unaffected, and you can restore it any time.")
            }
        } actions: {
            AdButton(label: "Skip this date", variant: .danger, full: true) {
                if let o = confirming {
                    Task { await store.setSkip(rule.id, day: o.day, skipped: true) }
                }
                confirming = nil
            }
            AdButton(label: "Keep it scheduled", variant: .secondary, full: true) {
                confirming = nil
            }
        }
    }

    private func occurrenceRow(_ rule: RecurringRule, _ o: RuleOccurrence, first: Bool) -> some View {
        let isSkipped = o.skipped
        let isToday = o.isToday
        let dayNumber = o.day.day
        let working = store.isBusy(.skip(rule.id, o.day))

        return HStack(spacing: 12) {
            Text("\(dayNumber)")
                .font(AdFont.sans(14, weight: .bold))
                .monospacedDigit()
                .strikethrough(isSkipped)
                .foregroundStyle(isSkipped ? c.fgMuted : (isToday ? c.onAccent : c.fg))
                .frame(width: 34, height: 34)
                .background(isSkipped ? .clear : (isToday ? c.accent : c.surfaceRaised), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSkipped ? c.border : (isToday ? .clear : c.cardEdge)))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(AdminDates.short(o.day.date())).strikethrough(isSkipped, color: c.fgMuted).foregroundStyle(isSkipped ? c.fgMuted : c.fg))\(isToday ? Text(" · today").fontWeight(.bold).foregroundStyle(c.accent) : Text(""))")
                    .font(AdFont.sans(14, weight: .semibold))
                Text(isSkipped ? "Skipped — nothing will send" : o.time.display)
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if isSkipped {
                    Task { await store.setSkip(rule.id, day: o.day, skipped: false) }
                } else {
                    confirming = o
                }
            } label: {
                Text(isSkipped ? "Restore" : "Skip")
                    .font(AdFont.sans(12, weight: .semibold))
                    .foregroundStyle(isSkipped ? c.fg : c.destructive)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(isSkipped ? c.surfaceRaised : .clear, in: .rect(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSkipped ? c.cardEdge : c.border))
                    .opacity(working ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .overlay(alignment: .top) {
            if !first { c.cardEdge.frame(height: 1) }
        }
    }
}
