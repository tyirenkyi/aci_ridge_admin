//
//  TranslationDTO.swift
//  ACI Admin
//
//  Wire shapes for /api/translations. Unlike the other resources these rows are not
//  Postgres columns: a translation is one language's object inside the devotional
//  row's `translations` JSONB, written by the audio worker. So every field here is
//  optional — an entry mid-job legitimately has text but no audio yet — and the
//  timestamps stay Strings, parsed leniently, rather than letting one odd value
//  from the worker fail the whole screen's decode.
//

import Foundation

// MARK: - Queue

/// `GET /api/translations/status?lang=` — every devotional date with the state of
/// one language, including the days that have no translation at all.
nonisolated struct TranslationStatusDTO: Decodable, Sendable {
    let lang: String
    let dates: [Row]

    nonisolated struct Row: Decodable, Sendable {
        let id: String
        /// `DD/MM/YYYY`, the devotional table's own spelling.
        let date: String
        /// `none` when the day has never been translated.
        let status: String
        let audioStale: Bool
        let needsReview: [String]
        let reviewNote: String?

        enum CodingKeys: String, CodingKey {
            case id, date, status
            case audioStale = "audio_stale"
            case needsReview = "needs_review"
            case reviewNote = "review_note"
        }
    }
}

// MARK: - One day's translation

/// One language's entry. The server merges patches into this shallowly, so a
/// response after a status change carries the whole entry, not just what changed.
nonisolated struct TranslationEntryDTO: Decodable, Sendable {
    let status: String?
    let audioStale: Bool?
    let title: String?
    let verse: String?
    let scripture: String?
    let declarations: String?
    let prayers: [String]?
    let paragraphs: [String]?
    let needsReview: [String]?
    let translatedAt: String?
    let voice: String?
    let ttsModel: String?
    let reviewNote: String?
    let reviewedBy: String?
    let reviewedAt: String?

    enum CodingKeys: String, CodingKey {
        case status, title, verse, scripture, declarations, prayers, paragraphs, voice
        case audioStale = "audio_stale"
        case needsReview = "needs_review"
        case translatedAt = "translated_at"
        case ttsModel = "tts_model"
        case reviewNote = "review_note"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
    }
}

/// The English the translation was made from. Same shape, no status.
nonisolated struct TranslationSourceDTO: Decodable, Sendable {
    let title: String?
    let verse: String?
    let scripture: String?
    let declarations: String?
    let prayers: [String]?
    let paragraphs: [String]?
}

/// `GET /api/translations/DD-MM-YYYY/{es|fr}`
nonisolated struct TranslationDetailDTO: Decodable, Sendable {
    let id: String
    let date: String
    let lang: String
    let translation: TranslationEntryDTO
    let source: TranslationSourceDTO
}

/// `PATCH /api/translations/DD-MM-YYYY/{es|fr}` — the merged entry comes back.
nonisolated struct TranslationPatchResultDTO: Decodable, Sendable {
    let id: String
    let date: String
    let lang: String
    let translation: TranslationEntryDTO
}

// MARK: - Audio

/// `GET /api/translations/DD-MM-YYYY/{es|fr}/audio-urls`
///
/// One devotional is several recordings, not one: the narration, the declarations,
/// and one file per prayer — each with its English counterpart under a `source_`
/// key, plus the language-neutral music bed. Keys are open-ended (`prayer_3` exists
/// only if there is a third prayer), so this stays a dictionary and the domain layer
/// decides what to pair up.
nonisolated struct TranslationAudioDTO: Decodable, Sendable {
    let id: String
    let date: String
    let lang: String
    /// Signed-URL lifetime in seconds. They expire, so a long review re-fetches.
    let expiresIn: Int
    let urls: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, date, lang, urls
        case expiresIn = "expires_in"
    }
}
