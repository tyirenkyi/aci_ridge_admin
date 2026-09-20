//
//  ReviewScreens.swift
//  ACI Admin
//
//  Translation review: the per-language queue, one day under review, and the
//  audio panel. Ported from admin-screens-c.jsx / admin-audio.jsx, then wired to
//  /api/translations.
//
//  Two things differ from the prototype, because the server differs from it.
//  Only devotionals are translated, so the queue has no notice or recurring rows;
//  and a devotional is several recordings rather than one, so the panel picks a
//  track before it plays anything.
//

import SwiftUI

// MARK: - Review queue

struct AdReviewQueueView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    let onOpen: (TranslationSummary) -> Void

    /// The corpus is every devotional ever published, and all of it stays in the
    /// queue once decided. Only the recent decisions are worth showing.
    private static let decidedShown = 30

    private var lang: Language { store.reviewLanguage }

    var body: some View {
        AdShell(onRefresh: { await store.loadReview(lang, force: true) }) {
            AdTitle("Review", sub: "Read the draft, then approve it or send it back with a note. Rejected days fall back to English.")

            AdSegmented(
                options: Language.all.map {
                    AdSegmentOption(label: $0.native, value: $0.value, badge: store.pendingCount($0))
                },
                selection: Binding(
                    get: { store.reviewLanguage.value },
                    set: { v in store.reviewLanguage = Language.named(v) ?? .french }
                )
            )
            .padding(.horizontal, 20)

            AdLoadState(store.reviewQueue(lang), retry: { await store.loadReview(lang, force: true) }) { rows in
                let pending = rows.filter { $0.status == .pending }
                let decided = rows.filter { $0.status != .pending }

                if rows.isEmpty {
                    AdEmptyState(
                        icon: "globe",
                        title: "Nothing to review in \(lang.native)",
                        message: "Days appear here once a translation job has run for them."
                    )
                } else if pending.isEmpty {
                    allClear
                }

                group(label: "Awaiting review", rows: pending, muted: false)
                group(label: "Decided", rows: Array(decided.prefix(Self.decidedShown)), muted: true)

                if decided.count > Self.decidedShown {
                    Text("Showing the \(Self.decidedShown) most recent decisions of \(decided.count).")
                        .font(AdFont.sans(11.5))
                        .foregroundStyle(c.fgMuted)
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                }
            }
        }
        .task(id: lang.value) { await store.loadReview(lang) }
    }

    private var allClear: some View {
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

    @ViewBuilder
    private func group(label: String, rows: [TranslationSummary], muted: Bool) -> some View {
        if !rows.isEmpty {
            AdEyebrow("\(label) · \(rows.count)")
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    itemCard(row, muted: muted)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func itemCard(_ item: TranslationSummary, muted: Bool) -> some View {
        Button {
            onOpen(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Daily devotion".uppercased())
                        .font(AdFont.label())
                        .tracking(1.4)
                        .foregroundStyle(c.accent)

                    Text(item.dayLabel)
                        .font(AdFont.sans(14.5, weight: .semibold))
                        .foregroundStyle(c.fg)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 5)

                    if !flags(item).isEmpty {
                        HStack(spacing: 7) {
                            ForEach(flags(item), id: \.self) { flag in
                                AdFlagPill(text: flag)
                            }
                        }
                        .padding(.top, 7)
                    }

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

    /// What the job itself flagged. `needs_review` is machine-generated — the
    /// scripture matcher is the usual source — and `audio_stale` means somebody
    /// edited the text after it was voiced.
    private func flags(_ item: TranslationSummary) -> [String] {
        var out = item.needsReview.map { $0 == "scripture" ? "Check passage" : $0.capitalized }
        if item.audioStale { out.append("Audio behind text") }
        return out
    }
}

/// A small warning pill. Distinct from AdChip, which carries a lifecycle status.
struct AdFlagPill: View {
    @Environment(\.palette) private var c
    let text: String

    var body: some View {
        Text(text)
            .font(AdFont.sans(10.5, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(c.fgSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(c.surfaceRaised, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.border))
    }
}

// MARK: - One day under review

struct AdReviewItemView: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @Environment(AdminStore.self) private var store

    let itemID: TranslationSummary.ID

    @State private var rejecting = false
    @State private var note = ""
    @State private var working = false

    private var summary: TranslationSummary? { store.summary(itemID) }
    private var lang: Language { summary.flatMap { Language.named($0.lang) } ?? store.reviewLanguage }

    var body: some View {
        AdShell(onRefresh: { await store.loadReviewDetail(itemID, force: true) }) {
            if let summary {
                AdLoadState(store.reviewDetail(itemID),
                            retry: { await store.loadReviewDetail(itemID, force: true) }) { detail in
                    content(summary, detail)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AdTopBar(title: "\(lang.native) · Daily devotion") {
                if let status = summary?.status {
                    AdChip(status: ChipStatus(status))
                }
            }
        }
        .task { await store.loadReviewDetail(itemID) }
    }

    @ViewBuilder
    private func content(_ summary: TranslationSummary, _ detail: TranslationDetail) -> some View {
        AdTitle(
            summary.dayLabelLong,
            sub: "\(detail.fields.count) field\(detail.fields.count == 1 ? "" : "s") translated"
        )

        if detail.audioStale {
            AdHintRow(icon: "waveform.badge.exclamationmark",
                      text: "The text was edited after this was voiced, so the recordings are behind it. Re-run an audio-only job before approving.")
        }

        AdEyebrow(text: "The draft") {
            Text("EN → \(lang.code)")
                .font(AdFont.label())
                .tracking(1.4)
                .foregroundStyle(c.accent)
        }
        VStack(spacing: 8) {
            ForEach(detail.fields, id: \.self) { field in
                fieldCard(field)
            }
        }
        .padding(.horizontal, 20)

        if !detail.tracks.isEmpty {
            AdEyebrow(text: "Translated audio") {
                Text("\(detail.tracks.count) recording\(detail.tracks.count == 1 ? "" : "s")")
                    .font(AdFont.label())
                    .tracking(1.4)
                    .foregroundStyle(c.fgMuted)
            }
            AdAudioPanel(tracks: detail.tracks, langCode: lang.code,
                         voice: detail.voice, recorded: detail.recordedLabel)
                .padding(.horizontal, 20)
        }

        if summary.status != .pending {
            decidedCard(summary, detail)
        } else if rejecting {
            rejectForm
        } else {
            pendingActions
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
                Text(field.source.isEmpty ? "—" : field.source)
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
                // An empty draft is the gap review exists to catch, so say so
                // rather than rendering nothing.
                Text(field.draft.isEmpty ? "Not translated" : field.draft)
                    .font(field.usesSerif ? AdFont.serif(14.5) : AdFont.sans(14.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(field.draft.isEmpty ? c.destructive : c.fg)
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

    private func decidedCard(_ summary: TranslationSummary, _ detail: TranslationDetail) -> some View {
        AdCard {
            Text(summary.status == .approved
                 ? "Approved — members reading in \(lang.native) see this translation."
                 : "Sent back with a note. Members see the English source for this day, so there is no gap.")
                .font(AdFont.sans(13))
                .lineSpacing(3)
                .foregroundStyle(c.fgSecondary)
            if let note = summary.note ?? detail.note {
                Text("\u{201C}\(note)\u{201D}")
                    .font(AdFont.sans(12.5))
                    .italic()
                    .lineSpacing(2.5)
                    .foregroundStyle(c.fgMuted)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
                    .padding(.top, 10)
            }
            if let by = detail.reviewedBy {
                Text("Decided by \(by)")
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.fgMuted)
                    .padding(.top, 8)
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
                         disabled: working || note.trimmed.isEmpty) {
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
                AdButton(label: "Send back", variant: .danger, disabled: working) {
                    rejecting = true
                }
                AdButton(label: "Approve", icon: "checkmark", full: true, disabled: working) {
                    decide(.approved)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
        }
    }

    private func decide(_ status: ReviewStatus) {
        working = true
        Task {
            defer { working = false }
            do throws(APIError) {
                try await store.decide(itemID, status, note: note)
                store.flash(status == .approved
                            ? "Approved — published to readers"
                            : "Sent back — this day stays in English")
                dismiss()
            } catch {
                // Stay on the screen: the decision didn't happen, and the
                // reviewer needs to see that before navigating away.
                store.flashError(error)
            }
        }
    }
}

// MARK: - Translated audio panel

/// A day's narration is several files — the main reading, the declarations, one
/// per prayer, and the shared music bed — so the panel picks a track first, then
/// plays it. The English twin of the selected track sits behind the second
/// toggle, which is the whole point: a reviewer A/Bs the same passage.
struct AdAudioPanel: View {
    @Environment(\.palette) private var c

    let tracks: [AudioTrack]
    let langCode: String
    let voice: String?
    let recorded: String?

    @State private var player = ReviewAudioPlayer()
    @State private var selectedKey: String
    @State private var usingSource = false

    /// Decorative. The bars are a fixed silhouette; only how far the fill has
    /// travelled is real, driven by the player's position.
    private static let bars: [Double] = [
        0.35, 0.6, 0.45, 0.8, 1, 0.7, 0.5, 0.9, 0.65, 0.4, 0.75, 1, 0.55, 0.35, 0.6, 0.85, 0.5, 0.7, 0.95, 0.6,
        0.4, 0.8, 0.55, 0.7, 0.45, 0.9, 0.6, 0.35, 0.75, 0.5, 0.65, 0.85, 0.4, 0.7, 0.55, 0.95, 0.6, 0.45, 0.8, 0.5,
    ]

    init(tracks: [AudioTrack], langCode: String, voice: String?, recorded: String?) {
        self.tracks = tracks
        self.langCode = langCode
        self.voice = voice
        self.recorded = recorded
        _selectedKey = State(initialValue: tracks.first?.key ?? "")
    }

    private var track: AudioTrack? {
        tracks.first { $0.key == selectedKey } ?? tracks.first
    }

    private var currentURL: URL? {
        guard let track else { return nil }
        return usingSource ? track.source : track.translated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trackPicker

            if let track {
                sourceToggle(track)

                HStack(spacing: 13) {
                    playButton
                    scrubber
                }

                HStack(spacing: 10) {
                    Text(clock(player.position))
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                        Text(caption(track))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(player.isReady ? clock(player.duration) : "--:--")
                }
                .font(AdFont.sans(11.5))
                .monospacedDigit()
                .foregroundStyle(c.fgMuted)
                .padding(.top, 9)

                footer
            }
        }
        .padding(EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15))
        .background(c.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(player.isPlaying ? c.glowSoft : c.cardEdge))
        .task(id: "\(selectedKey)|\(usingSource)") {
            player.load(currentURL, trackKey: selectedKey, usingSource: usingSource)
        }
        .onDisappear { player.tearDown() }
    }

    // MARK: Pieces

    private var trackPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tracks) { t in
                    let on = t.key == selectedKey
                    Button {
                        guard !on else { return }
                        selectedKey = t.key
                        // The bed has no translation, so an EN-only track must
                        // not leave the toggle pointing at a file that isn't there.
                        usingSource = !t.hasTranslation
                    } label: {
                        Text(t.label)
                            .font(AdFont.sans(11.5, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? c.onAccent : c.fgSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(on ? c.accent : c.surfaceRaised, in: .rect(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? .clear : c.border))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private func sourceToggle(_ track: AudioTrack) -> some View {
        HStack(spacing: 6) {
            if track.hasTranslation {
                sourceButton(source: false, label: langCode, enabled: true)
            }
            if track.hasSource {
                sourceButton(source: true, label: "English", enabled: true)
            }
            Spacer(minLength: 0)
            if !track.hasTranslation {
                Text("Same in every language")
                    .font(AdFont.sans(11))
                    .foregroundStyle(c.fgMuted)
            }
        }
        .padding(.bottom, 13)
    }

    private var playButton: some View {
        Button {
            player.toggle()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17))
                .foregroundStyle(c.onAccent)
                .frame(width: 46, height: 46)
                .background(player.isReady ? c.accent : c.progressTrack, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!player.isReady)
    }

    private var scrubber: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(Self.bars.enumerated()), id: \.offset) { i, h in
                    let played = Double(i) / Double(Self.bars.count) <= player.fraction
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
                        player.seek(fraction: value.location.x / geo.size.width)
                    }
            )
        }
        .frame(height: 38)
        .opacity(player.isReady ? 1 : 0.5)
    }

    @ViewBuilder
    private var footer: some View {
        let line = player.failed
            ? "That recording wouldn't load. Pull to refresh — the signed links expire after an hour."
            : "\(recorded.map { "Recorded \($0) · " } ?? "")listen right through before approving."
        Text(line)
            .font(AdFont.sans(11.5))
            .lineSpacing(2.5)
            .foregroundStyle(player.failed ? c.destructive : c.fgMuted)
            .padding(.top, 10)
            .overlay(alignment: .top) { c.cardEdge.frame(height: 1) }
            .padding(.top, 11)
    }

    private func sourceButton(source: Bool, label: String, enabled: Bool) -> some View {
        let on = usingSource == source
        return Button {
            usingSource = source
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
        .disabled(!enabled)
    }

    private func caption(_ track: AudioTrack) -> String {
        if usingSource { return "English source recording" }
        return voice ?? track.label
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
