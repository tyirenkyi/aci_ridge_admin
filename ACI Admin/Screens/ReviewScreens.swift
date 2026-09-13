//
//  ReviewScreens.swift
//  ACI Admin
//
//  Translation review queue, the single-item review screen and the
//  translated-audio panel. Ported from admin-screens-c.jsx / admin-audio.jsx.
//

import SwiftUI
import Combine

// MARK: - Review queue

struct AdReviewQueueView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    let onOpen: (TranslationItem) -> Void

    private var lang: Language { store.reviewLanguage }
    private var items: [TranslationItem] { store.translations[lang.value] ?? [] }

    var body: some View {
        AdShell {
            AdTitle("Review", sub: "Read the draft, then approve it or send it back with a note. Rejected days fall back to English.")

            AdSegmented(
                options: Language.all.map {
                    AdSegmentOption(label: $0.native, value: $0.value, badge: store.pendingCount($0))
                },
                selection: Binding(
                    get: { store.reviewLanguage.value },
                    set: { v in store.reviewLanguage = Language.all.first { $0.value == v } ?? .french }
                )
            )
            .padding(.horizontal, 20)

            let pending = items.filter { $0.status == .pending }
            let done = items.filter { $0.status != .pending }

            if pending.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.greenFg)
                        .frame(width: 34, height: 34)
                        .background(c.greenBg, in: .circle)
                    Text("Nothing waiting in \(lang.native). Everything published is approved.")
                        .font(AdFont.sans(13.5))
                        .lineSpacing(3)
                        .foregroundStyle(c.fgSecondary)
                        .padding(.top, 5)
                }
                .padding(EdgeInsets(top: 26, leading: 20, bottom: 0, trailing: 20))
            }

            group(label: "Awaiting review", rows: pending, muted: false)
            group(label: "Decided", rows: done, muted: true)
        }
    }

    @ViewBuilder
    private func group(label: String, rows: [TranslationItem], muted: Bool) -> some View {
        if !rows.isEmpty {
            AdEyebrow("\(label) · \(rows.count)")
            VStack(spacing: 8) {
                ForEach(rows) { item in
                    itemCard(item, muted: muted)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func itemCard(_ item: TranslationItem, muted: Bool) -> some View {
        Button {
            onOpen(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.type.uppercased())
                        .font(AdFont.label())
                        .tracking(1.4)
                        .foregroundStyle(c.accent)

                    Text(item.title)
                        .font(AdFont.sans(14.5, weight: .semibold))
                        .foregroundStyle(c.fg)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 5)

                    HStack(spacing: 7) {
                        Text(item.dayLabel)
                        Text("·").opacity(0.5)
                        Text("\(item.fields.count) field\(item.fields.count == 1 ? "" : "s")")
                        if let audio = item.audio {
                            Text("·").opacity(0.5)
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 10))
                                Text(audio.duration)
                            }
                            .foregroundStyle(c.accent)
                        }
                    }
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.fgMuted)
                    .padding(.top, 4)

                    if item.status == .rejected, let note = item.note {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(AdFont.sans(11.5))
                            .lineSpacing(2.5)
                            .foregroundStyle(c.fgSecondary)
                            .multilineTextAlignment(.leading)
                            .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(c.rejectNoteBg, in: .rect(cornerRadius: 9))
                            .padding(.top, 9)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AdChip(status: ChipStatus(item.status))
            }
            .padding(14)
            .background(c.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.cardEdge))
            .opacity(muted ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One item under review

struct AdReviewItemView: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @Environment(AdminStore.self) private var store

    let itemID: TranslationItem.ID

    @State private var rejecting = false
    @State private var note = ""

    private var lang: Language { store.reviewLanguage }
    private var item: TranslationItem? { store.translation(itemID) }

    var body: some View {
        if let item {
            content(item)
        }
    }

    private func content(_ item: TranslationItem) -> some View {
        AdShell {
            AdTitle(
                item.title,
                sub: "\(item.dayLabelLong) · \(item.fields.count) field\(item.fields.count == 1 ? "" : "s") translated"
            )

            AdEyebrow(text: "The draft") {
                Text("EN → \(lang.code)")
                    .font(AdFont.label())
                    .tracking(1.4)
                    .foregroundStyle(c.accent)
            }
            VStack(spacing: 8) {
                ForEach(item.fields, id: \.self) { field in
                    fieldCard(field)
                }
            }
            .padding(.horizontal, 20)

            if let audio = item.audio {
                AdEyebrow(text: "Translated audio") {
                    Text(audio.duration)
                        .font(AdFont.label())
                        .tracking(1.4)
                        .foregroundStyle(c.fgMuted)
                }
                AdAudioPanel(audio: audio, langCode: lang.code)
                    .padding(.horizontal, 20)
            }

            if item.status != .pending {
                decidedCard(item)
            } else if rejecting {
                rejectForm
            } else {
                pendingActions
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: "\(lang.native) · \(item.type)") {
                AdChip(status: ChipStatus(item.status))
            }
        }
    }

    // MARK: Field card

    private func fieldCard(_ field: TranslationField) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(field.label) · English".uppercased())
                    .font(AdFont.label(10))
                    .tracking(1.6)
                    .foregroundStyle(c.fgMuted)
                Text(field.source)
                    .font(AdFont.sans(13))
                    .lineSpacing(3)
                    .foregroundStyle(c.fgMuted)
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(lang.code)
                    .font(AdFont.label(10))
                    .tracking(1.6)
                    .foregroundStyle(c.accent)
                Text(field.draft)
                    .font(field.usesSerif ? AdFont.serif(14.5) : AdFont.sans(14.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(c.fg)
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 13, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.draftBg)
            .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
        }
        .background(c.card, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.cardEdge))
    }

    // MARK: States

    private func decidedCard(_ item: TranslationItem) -> some View {
        AdCard {
            Text(item.status == .approved
                 ? "Approved — members reading in \(lang.native) see this translation."
                 : "Sent back with a note. Members see the English source for this day, so there is no gap.")
                .font(AdFont.sans(13))
                .lineSpacing(3)
                .foregroundStyle(c.fgSecondary)
            if let note = item.note {
                Text("\u{201C}\(note)\u{201D}")
                    .font(AdFont.sans(12.5))
                    .italic()
                    .lineSpacing(2.5)
                    .foregroundStyle(c.fgMuted)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                    .padding(.top, 10)
            }
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
    }

    private var rejectForm: some View {
        Group {
            AdEyebrow("Note for the translator")
            AdField(label: "What needs changing", text: $note,
                    placeholder: "Be specific — which phrase, and what it should say.",
                    hint: "Members see the English source for this day until a new draft is approved.",
                    rows: 3, chars: 200)
            HStack(spacing: 8) {
                AdButton(label: "Cancel", variant: .secondary) {
                    rejecting = false
                }
                AdButton(label: "Send back", variant: .danger, full: true,
                         disabled: note.trimmingCharacters(in: .whitespaces).isEmpty) {
                    decide(.rejected)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
        }
    }

    private var pendingActions: some View {
        Group {
            AdHintRow(icon: "globe",
                      text: "Approving publishes this to \(lang.native) readers. Sending it back keeps the day in English.")
            HStack(spacing: 8) {
                AdButton(label: "Send back", variant: .danger) {
                    rejecting = true
                }
                AdButton(label: "Approve", icon: "checkmark", full: true) {
                    decide(.approved)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
        }
    }

    private func decide(_ status: ReviewStatus) {
        if var rows = store.translations[lang.value],
           let i = rows.firstIndex(where: { $0.id == itemID }) {
            rows[i].status = status
            rows[i].note = status == .rejected && !note.isEmpty ? note : nil
            store.translations[lang.value] = rows
        }
        store.flash(status == .approved
                    ? "Approved — published to readers"
                    : "Sent back — this day stays in English")
        dismiss()
    }
}

// MARK: - Translated audio panel

struct AdAudioPanel: View {
    @Environment(\.palette) private var c
    let audio: AudioInfo
    let langCode: String

    @State private var playing = false
    @State private var position = 0
    @State private var source: String

    private static let bars: [Double] = [
        0.35, 0.6, 0.45, 0.8, 1, 0.7, 0.5, 0.9, 0.65, 0.4, 0.75, 1, 0.55, 0.35, 0.6, 0.85, 0.5, 0.7, 0.95, 0.6,
        0.4, 0.8, 0.55, 0.7, 0.45, 0.9, 0.6, 0.35, 0.75, 0.5, 0.65, 0.85, 0.4, 0.7, 0.55, 0.95, 0.6, 0.45, 0.8, 0.5,
    ]



    init(audio: AudioInfo, langCode: String) {
        self.audio = audio
        self.langCode = langCode
        _source = State(initialValue: langCode)
    }

    private var total: Int { audio.totalSeconds }
    private var fraction: Double { total > 0 ? Double(position) / Double(total) : 0 }

    private func fmt(_ n: Int) -> String {
        "\(n / 60):" + String(format: "%02d", n % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // which recording
            HStack(spacing: 6) {
                sourceButton(value: langCode, label: langCode)
                sourceButton(value: "EN", label: "English")
                Spacer(minLength: 0)
                Text(audio.size)
                    .font(AdFont.sans(11))
                    .monospacedDigit()
                    .foregroundStyle(c.fgMuted)
            }
            .padding(.bottom, 13)

            HStack(spacing: 13) {
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(c.onAccent)
                        .frame(width: 46, height: 46)
                        .background(c.accent, in: .circle)
                }
                .buttonStyle(.plain)

                // waveform doubles as the scrubber
                GeometryReader { geo in
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(Self.bars.enumerated()), id: \.offset) { i, h in
                            let played = Double(i) / Double(Self.bars.count) <= fraction
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(played ? c.accent : c.progressTrack)
                                .frame(maxWidth: .infinity)
                                .frame(height: max(3, h * 38))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let f = min(1, max(0, value.location.x / geo.size.width))
                                position = Int(Double(total) * f)
                            }
                    )
                }
                .frame(height: 38)
            }

            HStack(spacing: 10) {
                Text(fmt(position))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                    Text(source == "EN" ? "English source recording" : audio.voice)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(audio.duration)
            }
            .font(AdFont.sans(11.5))
            .monospacedDigit()
            .foregroundStyle(c.fgMuted)
            .padding(.top, 9)

            Text("Recorded \(audio.recorded) · listen right through before approving.")
                .font(AdFont.sans(11.5))
                .lineSpacing(2.5)
                .foregroundStyle(c.fgMuted)
                .padding(.top, 10)
                .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                .padding(.top, 11)
        }
        .padding(EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15))
        .background(c.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(playing ? c.glowSoft : c.cardEdge))
        // Ticks only while playing. An always-on Timer.publish keeps the run loop
        // busy forever, which stops the app ever reporting itself idle — UI tests
        // then hang waiting to interact with this screen.
        .task(id: playing) {
            guard playing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, playing else { return }
                if position + 1 >= total {
                    position = total
                    playing = false
                    return
                }
                position += 1
            }
        }
    }

    private func sourceButton(value: String, label: String) -> some View {
        let on = source == value
        return Button {
            source = value
            position = 0
            playing = false
        } label: {
            Text(label)
                .font(AdFont.sans(11.5, weight: on ? .bold : .regular))
                .tracking(0.6)
                .foregroundStyle(on ? c.fg : c.fgMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(on ? c.surfaceRaised : .clear, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? c.border : .clear))
        }
        .buttonStyle(.plain)
    }
}
