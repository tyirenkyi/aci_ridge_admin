//
//  TranslationMapping.swift
//  ACI Admin
//
//  Wire → domain for translations. This is the only place that knows the shape of
//  the `urls` bag and how a devotional's parts pair up with their English
//  counterparts, so the screens can just take a list of tracks.
//

import Foundation

// MARK: - Queue rows

nonisolated extension TranslationStatusDTO {
    /// Days that have never been translated come back as `none`; they are not
    /// review work, so they are dropped here rather than filtered in every screen.
    var summaries: [TranslationSummary] {
        dates.compactMap { row in
            guard let status = ReviewStatus(wire: row.status) else { return nil }
            return TranslationSummary(
                date: row.date,
                lang: lang,
                status: status,
                note: row.reviewNote,
                audioStale: row.audioStale,
                needsReview: row.needsReview
            )
        }
        // Newest first: review works backwards from today, and the server sorts
        // ascending because the audio tooling reads it that way.
        .sorted { ($0.day ?? .today) > ($1.day ?? .today) }
    }
}

// MARK: - Fields

nonisolated extension TranslationDetailDTO {
    /// English beside the draft, in reading order. A part missing on both sides is
    /// left out entirely; one missing on a single side still shows, because an
    /// untranslated paragraph is exactly the kind of gap review exists to catch.
    var fields: [TranslationField] {
        var out: [TranslationField] = []

        func add(_ label: String, _ en: String?, _ target: String?, serif: Bool) {
            let en = en?.trimmed ?? ""
            let target = target?.trimmed ?? ""
            guard !en.isEmpty || !target.isEmpty else { return }
            out.append(TranslationField(label: label, source: en, draft: target, usesSerif: serif))
        }

        add("Title", source.title, translation.title, serif: false)
        add("Verse", source.verse, translation.verse, serif: false)
        add("Scripture", source.scripture, translation.scripture, serif: true)
        add("Declarations", source.declarations, translation.declarations, serif: true)

        let prayers = source.prayers ?? []
        let draftPrayers = translation.prayers ?? []
        for i in 0..<max(prayers.count, draftPrayers.count) {
            add("Prayer \(i + 1)", prayers[safe: i], draftPrayers[safe: i], serif: false)
        }

        let paragraphs = source.paragraphs ?? []
        let draftParagraphs = translation.paragraphs ?? []
        for i in 0..<max(paragraphs.count, draftParagraphs.count) {
            add("Paragraph \(i + 1)", paragraphs[safe: i], draftParagraphs[safe: i], serif: true)
        }

        return out
    }
}

// MARK: - Tracks

nonisolated extension TranslationAudioDTO {
    /// Pairs each recording with its English counterpart.
    ///
    /// Keys arrive flat — `main`, `declaration`, `prayer_1`, `prayer_2`, … and a
    /// `source_` twin for each — because how many prayers a day has is not fixed.
    /// Prayers are ordered numerically, not by string, so `prayer_10` doesn't sort
    /// between 1 and 2.
    var tracks: [AudioTrack] {
        func url(_ key: String) -> URL? { urls[key].flatMap(URL.init(string:)) }

        var out: [AudioTrack] = []

        func add(_ key: String, _ label: String) {
            let track = AudioTrack(key: key, label: label,
                                   translated: url(key), source: url("source_\(key)"))
            if track.isPlayable { out.append(track) }
        }

        add("main", "Narration")
        add("declaration", "Declarations")

        let prayerNumbers = urls.keys
            .compactMap { key -> Int? in
                guard key.hasPrefix("prayer_") else { return nil }
                return Int(key.dropFirst("prayer_".count))
            }
            .sorted()
        for n in prayerNumbers {
            add("prayer_\(n)", "Prayer \(n)")
        }

        // The music bed is the same file for every language, so it has no
        // translated twin and nothing to compare — it rides along so a reviewer
        // can hear what sits under the narration.
        if let bed = url("background") {
            out.append(AudioTrack(key: "background", label: "Music bed",
                                  translated: nil, source: bed))
        }

        return out
    }
}

// MARK: - The whole screen

nonisolated extension TranslationDetail {
    /// Audio is a second request and is allowed to fail on its own: a reviewer can
    /// still read the text when the signing call is down, so `audio` is optional.
    init(_ dto: TranslationDetailDTO, audio: TranslationAudioDTO?) {
        self.init(
            status: ReviewStatus(wire: dto.translation.status ?? "draft") ?? .pending,
            note: dto.translation.reviewNote,
            audioStale: dto.translation.audioStale ?? false,
            fields: dto.fields,
            tracks: audio?.tracks ?? [],
            voice: dto.translation.voice,
            translatedAt: dto.translation.translatedAt.flatMap(APIDate.parse),
            reviewedBy: dto.translation.reviewedBy
        )
    }

    /// After a decision the server returns the merged entry; the text and audio
    /// did not change, so only the review state is taken from it.
    func applying(_ entry: TranslationEntryDTO) -> TranslationDetail {
        var copy = self
        if let status = entry.status.flatMap(ReviewStatus.init(wire:)) { copy.status = status }
        copy.note = entry.reviewNote
        copy.audioStale = entry.audioStale ?? audioStale
        return copy
    }
}

// MARK: - Small helpers

private nonisolated extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
