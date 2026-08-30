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
        AdShell {
            AdTitle("Upcoming events", sub: "What shows on the church website and the app's events list.")

            AdButton(label: "New event", icon: "plus", full: true) {
                onCompose(nil)
            }
            .padding(.horizontal, 20)

            AdEyebrow("\(store.events.count) events")
            VStack(spacing: 8) {
                ForEach(store.events) { event in
                    eventCard(event)
                }
            }
            .padding(.horizontal, 20)
        }
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
                    detailRow(icon: "clock", text: e.timeLabel)
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

    @State private var name: String
    @State private var descriptionText: String
    @State private var timeLabel: String
    @State private var location: String
    @State private var confirmingUnpublish = false

    init(editing: ChurchEvent?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _descriptionText = State(initialValue: editing?.description ?? "")
        _timeLabel = State(initialValue: editing?.timeLabel ?? "")
        _location = State(initialValue: editing?.location ?? "")
    }

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !timeLabel.trimmingCharacters(in: .whitespaces).isEmpty
            && !location.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isPublished: Bool { editing?.status == .published }

    var body: some View {
        AdShell {
            AdTitle(
                Text("\(editing == nil ? "Add an " : "Edit the ")\(Text("event.").italic().foregroundStyle(c.accent))"),
                sub: "Events appear in the app and on the website until their date passes."
            )

            AdField(label: "Name", text: $name, placeholder: "Night of Worship", chars: 70)
            AdField(label: "Description", text: $descriptionText,
                    placeholder: "What happens, who it's for, anything to bring.", rows: 4, chars: 320)
            AdField(label: "Time label", text: $timeLabel, placeholder: "Friday, 6:00 pm — 9:00 pm",
                    hint: "Free text — write it the way you'd say it from the pulpit.")
            AdField(label: "Location", text: $location, placeholder: "Main auditorium · 31 Volta Street")

            AdEyebrow("Preview")
            AdCard {
                Text(name.isEmpty ? "Event name" : name)
                    .font(AdFont.display(20))
                    .foregroundStyle(c.fg)
                if !descriptionText.isEmpty {
                    Text(descriptionText)
                        .font(AdFont.sans(12.5))
                        .lineSpacing(3)
                        .foregroundStyle(c.fgSecondary)
                        .padding(.top, 7)
                }
                VStack(alignment: .leading, spacing: 5) {
                    previewRow(icon: "clock", text: timeLabel.isEmpty ? "Time label" : timeLabel, filled: !timeLabel.isEmpty)
                    previewRow(icon: "mappin.and.ellipse", text: location.isEmpty ? "Location" : location, filled: !location.isEmpty)
                }
                .padding(.top, 11)
                .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                .padding(.top, 11)
            }
            .padding(.horizontal, 20)

            if !ready {
                Text("Add a name, time label and location to publish this.")
                    .font(AdFont.sans(12))
                    .foregroundStyle(c.fgMuted)
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            }

            HStack(spacing: 8) {
                AdButton(label: "Save draft", variant: .secondary, disabled: !ready) {
                    finish("Draft saved")
                }
                AdButton(
                    label: isPublished ? "Save changes" : "Publish event",
                    full: true, disabled: !ready
                ) {
                    finish("Event published")
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
                AdTopBarAction(label: "Publish", enabled: ready) {
                    finish("Event published")
                }
            }
        }
        .adSheet(isPresented: $confirmingUnpublish, title: "Unpublish this event?") {
            Text("\(Text(name.isEmpty ? "This event" : name).fontWeight(.semibold).foregroundStyle(c.fg)) disappears from the app and the website straight away. Nothing is deleted — it returns to your drafts, so you can publish it again once details are settled.")
        } actions: {
            AdButton(label: "Unpublish — move to drafts", variant: .danger, full: true) {
                confirmingUnpublish = false
                finish("Unpublished — moved to drafts")
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

    private func finish(_ toast: String) {
        store.flash(toast)
        dismiss()
    }
}
