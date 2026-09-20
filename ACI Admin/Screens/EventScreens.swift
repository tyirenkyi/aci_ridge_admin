//
//  EventScreens.swift
//  ACI Admin
//
//  Events list and the event compose/edit screen with unpublish flow.
//  Ported from admin-screens-b.jsx.
//

import SwiftUI

// MARK: - Events list

struct AdEventsView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    let onCompose: (ChurchEvent?) -> Void

    var body: some View {
        AdShell(onRefresh: { await store.loadEvents(force: true) }) {
            AdTitle("Upcoming events", sub: "What shows on the church website and the app's events list.")

            AdButton(label: "New event", icon: "plus", full: true) {
                onCompose(nil)
            }
            .padding(.horizontal, 20)

            AdLoadState(store.eventsState, retry: { await store.loadEvents(force: true) }) { events in
                if events.isEmpty {
                    AdEmptyState(
                        icon: "calendar",
                        title: "Nothing on the calendar",
                        message: "Published events show in the app and on the website until their date passes."
                    )
                } else {
                    AdEyebrow("\(events.count) event\(events.count == 1 ? "" : "s")")
                    VStack(spacing: 8) {
                        ForEach(events) { event in
                            eventCard(event)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { await store.loadEvents() }
    }

    private func eventCard(_ e: ChurchEvent) -> some View {
        Button {
            onCompose(e)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(e.name)
                        .font(AdFont.display(18))
                        .foregroundStyle(c.fg)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AdChip(status: ChipStatus(e.status))
                }

                Text(e.description)
                    .font(AdFont.sans(12.5))
                    .lineSpacing(3)
                    .foregroundStyle(c.fgSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 5) {
                    detailRow(icon: "clock", text: e.displayTime)
                    detailRow(icon: "mappin.and.ellipse", text: e.location)
                }
                .padding(.top, 11)
                .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                .padding(.top, 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(c.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.cardEdge))
        }
        .buttonStyle(.plain)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(c.accent)
                .frame(width: 15)
            Text(text)
                .font(AdFont.sans(12))
                .foregroundStyle(c.fgSecondary)
        }
    }
}

// MARK: - Compose / edit an event

struct AdComposeEventView: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @Environment(AdminStore.self) private var store

    let editing: ChurchEvent?

    @State private var draft: EventDraft
    @State private var hasEnd: Bool
    @State private var confirmingUnpublish = false
    @State private var submitting = false
    @State private var eventID: String?

    init(editing: ChurchEvent?) {
        self.editing = editing
        _draft = State(initialValue: editing.map(EventDraft.init) ?? EventDraft())
        _hasEnd = State(initialValue: editing?.endsAt != nil)
        _eventID = State(initialValue: editing?.id)
    }

    /// The time label is filled in from the dates, so it is no longer something the
    /// admin has to supply.
    private var ready: Bool { draft.isReady }

    private var isPublished: Bool { editing?.status == .published }

    var body: some View {
        AdShell {
            AdTitle(
                Text("\(editing == nil ? "Add an " : "Edit the ")\(Text("event.").italic().foregroundStyle(c.accent))"),
                sub: "Events appear in the app and on the website until their date passes."
            )

            AdField(label: "Name", text: $draft.name, placeholder: "Night of Worship", chars: 70)
            AdField(label: "Description", text: $draft.description,
                    placeholder: "What happens, who it's for, anything to bring.", rows: 4, chars: 320)

            AdEyebrow("When")
            AdDateField(label: "Starts", date: $draft.startsAt,
                        hint: "Used to order events and to retire them once they've passed.")

            HStack(spacing: 11) {
                Text("Add an end time")
                    .font(AdFont.sans(13.5, weight: .semibold))
                    .foregroundStyle(c.fg)
                Spacer(minLength: 0)
                AdToggle(isOn: $hasEnd)
            }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 14, trailing: 20))

            if hasEnd {
                AdDateField(
                    label: "Ends",
                    date: Binding(
                        get: { draft.endsAt ?? draft.startsAt },
                        set: { draft.endsAt = $0 }
                    ),
                    earliest: draft.startsAt,
                    error: draft.timeRangeError
                )
            }

            AdField(label: "Time label", text: $draft.timeLabel, placeholder: "Friday, 6:00 pm — 9:00 pm",
                    hint: "Filled in from the dates above — change it if you'd say it differently.")

            AdField(label: "Location", text: $draft.location, placeholder: "Main auditorium · 31 Volta Street")

            AdEyebrow("Preview")
            AdCard {
                Text(draft.name.isEmpty ? "Event name" : draft.name)
                    .font(AdFont.display(20))
                    .foregroundStyle(c.fg)
                if !draft.description.isEmpty {
                    Text(draft.description)
                        .font(AdFont.sans(12.5))
                        .lineSpacing(3)
                        .foregroundStyle(c.fgSecondary)
                        .padding(.top, 7)
                }
                VStack(alignment: .leading, spacing: 5) {
                    previewRow(icon: "clock", text: draft.timeLabel.isEmpty ? draft.autoTimeLabel : draft.timeLabel, filled: true)
                    previewRow(icon: "mappin.and.ellipse", text: draft.location.isEmpty ? "Location" : draft.location, filled: !draft.location.isEmpty)
                }
                .padding(.top, 11)
                .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                .padding(.top, 11)
            }
            .padding(.horizontal, 20)

            if !ready {
                Text(draft.timeRangeError ?? "Add a name and location to publish this.")
                    .font(AdFont.sans(12))
                    .foregroundStyle(c.fgMuted)
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            }

            HStack(spacing: 8) {
                AdButton(label: "Save draft", variant: .secondary, disabled: !ready || submitting) {
                    submit(status: .draft, toast: "Draft saved")
                }
                AdButton(
                    label: isPublished ? "Save changes" : "Publish event",
                    full: true, disabled: !ready || submitting, loading: submitting
                ) {
                    submit(status: .published, toast: isPublished ? "Changes saved" : "Event published")
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))

            if isPublished {
                AdEyebrow("Visibility")
                AdCard {
                    HStack(spacing: 11) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(c.fgMuted)
                            .frame(width: 34, height: 34)
                            .background(c.surfaceRaised, in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.cardEdge))
                        Text("Live in the app and on the website. Unpublishing hides it from members and keeps it here as a draft.")
                            .font(AdFont.sans(12.5))
                            .lineSpacing(3)
                            .foregroundStyle(c.fgSecondary)
                    }
                    AdButton(label: "Unpublish event", icon: "eye.slash", variant: .danger, full: true) {
                        confirmingUnpublish = true
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: editing == nil ? "New event" : "Edit event") {
                AdTopBarAction(label: isPublished ? "Save" : "Publish",
                               enabled: ready && !submitting, loading: submitting) {
                    submit(status: .published, toast: isPublished ? "Changes saved" : "Event published")
                }
            }
        }
        .onChange(of: draft.startsAt) { _, _ in
            if !hasEnd { draft.endsAt = nil }
            draft.refreshTimeLabel()
        }
        .onChange(of: draft.endsAt) { _, _ in draft.refreshTimeLabel() }
        .onChange(of: hasEnd) { _, isOn in
            draft.endsAt = isOn ? max(draft.endsAt ?? draft.startsAt, draft.startsAt) : nil
            draft.refreshTimeLabel()
        }
        .onChange(of: draft.timeLabel) { old, new in
            // The first edit that isn't ours hands the label over for good.
            if new != draft.autoTimeLabel { draft.timeLabelEdited = true }
        }
        .adSheet(isPresented: $confirmingUnpublish, title: "Unpublish this event?") {
            Text("\(Text(draft.name.isEmpty ? "This event" : draft.name).fontWeight(.semibold).foregroundStyle(c.fg)) disappears from the app and the website straight away. Nothing is deleted — it returns to your drafts, so you can publish it again once details are settled.")
        } actions: {
            AdButton(label: "Unpublish — move to drafts", variant: .danger, full: true) {
                confirmingUnpublish = false
                unpublish()
            }
            AdButton(label: "Keep it live", variant: .secondary, full: true) {
                confirmingUnpublish = false
            }
        }
    }

    private func previewRow(icon: String, text: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(c.accent)
                .frame(width: 15)
            Text(text)
                .font(AdFont.sans(12))
                .foregroundStyle(filled ? c.fgSecondary : c.fgMuted)
        }
    }

    private func submit(status: EventStatus, toast: String) {
        guard !submitting else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do throws(APIError) {
                let saved = try await store.saveEvent(draft, id: eventID, status: status)
                eventID = saved.id
                finish(toast)
            } catch {
                store.flashError(error)
            }
        }
    }

    /// Unpublishing is just a status change — there is no separate endpoint.
    private func unpublish() {
        guard let eventID else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do throws(APIError) {
                _ = try await store.setEventStatus(eventID, .draft)
                finish("Unpublished — moved to drafts")
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
