//
//  Shared.swift
//  ACI Admin
//
//  Wire plumbing shared by every DTO: the error envelope, timestamp parsing, and
//  the patch-body machinery that keeps us on the right side of the API's strict
//  request validation.
//

import Foundation

// MARK: - Error envelope

/// Every failure from the server looks like this. There are no error codes.
nonisolated struct ErrorEnvelope: Decodable {
    let error: String
}

// MARK: - Timestamps

/// PostgREST hands back `2026-08-30T15:04:05.123456+00:00` — six fractional digits
/// and a numeric offset rather than `Z`. `ISO8601DateFormatter` is unreliable across
/// that shape, so parse through an explicit chain and pin it with a unit test.
nonisolated enum APIDate {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    private static let withMicroseconds = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
    private static let withMilliseconds = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    private static let withoutFraction  = formatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    private static let encoding         = formatter("yyyy-MM-dd'T'HH:mm:ss'Z'")

    static func parse(_ raw: String) -> Date? {
        for f in [withMicroseconds, withMilliseconds, withoutFraction] {
            if let date = f.date(from: raw) { return date }
        }
        // Last resort: rewrite the fractional part to exactly three digits and retry.
        // Covers any digit count the server might produce.
        if let normalised = normalisingFraction(raw) {
            return withMilliseconds.date(from: normalised)
        }
        return nil
    }

    /// Always UTC, always `Z`. The server's validator accepts `Z` alongside numeric
    /// offsets, and Ghana is UTC, so there is nothing to lose here.
    static func string(_ date: Date) -> String {
        encoding.string(from: date)
    }

    private static func normalisingFraction(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let afterDot = raw.index(after: dot)
        guard let endOfDigits = raw[afterDot...].firstIndex(where: { !$0.isNumber }) else { return nil }
        let digits = raw[afterDot..<endOfDigits]
        guard !digits.isEmpty else { return nil }
        let three = digits.count >= 3
            ? String(digits.prefix(3))
            : String(digits).padding(toLength: 3, withPad: "0", startingAt: 0)
        return String(raw[raw.startIndex..<afterDot]) + three + String(raw[endOfDigits...])
    }
}

nonisolated extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        // No key strategy on purpose: every DTO spells out its CodingKeys, which
        // documents the contract and sidesteps the camelCase `push` island inside
        // the otherwise snake_case send response.
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = APIDate.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Unrecognised timestamp: \(raw)")
                )
            }
            return date
        }
        return decoder
    }()
}

nonisolated extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIDate.string(date))
        }
        return encoder
    }()
}

// MARK: - Dynamic keys

nonisolated struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - JSON values

nonisolated enum JSONValue: Encodable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - Patch bodies

/// A PATCH payload built key by key.
///
/// Every write body on this API is validated strictly: an unknown key is a 400, so
/// re-encoding a decoded model is always a bug. Patches are a key bag rather than a
/// struct of optionals so that mistake has nowhere to live, and `isEmpty` lets the
/// caller skip a request the server would reject with "Nothing to change".
nonisolated struct PatchBody: Encodable, Sendable, Equatable {
    private(set) var fields: [String: JSONValue] = [:]

    init() {}

    var isEmpty: Bool { fields.isEmpty }

    mutating func set(_ key: String, _ value: String) { fields[key] = .string(value) }
    mutating func set(_ key: String, _ value: Int) { fields[key] = .int(value) }
    mutating func set(_ key: String, _ value: Bool) { fields[key] = .bool(value) }

    /// Sends an explicit JSON `null` for nil — which is how this API clears a
    /// nullable column. Only use it on fields the server marks nullable.
    mutating func set(_ key: String, nullable value: String?) {
        fields[key] = value.map(JSONValue.string) ?? .null
    }

    mutating func set(_ key: String, date value: Date?) {
        fields[key] = value.map { .string(APIDate.string($0)) } ?? .null
    }

    mutating func set(_ key: String, ifChanged new: String, from old: String) {
        guard new != old else { return }
        set(key, new)
    }

    mutating func set(_ key: String, ifChanged new: Date?, from old: Date?) {
        guard new != old else { return }
        set(key, date: new)
    }

    mutating func set(_ key: String, ifChanged new: Bool, from old: Bool) {
        guard new != old else { return }
        set(key, new)
    }

    /// For a nullable string field where "" in the UI means null on the wire.
    mutating func set(_ key: String, ifChangedNullable new: String, from old: String) {
        guard new != old else { return }
        set(key, nullable: new.isEmpty ? nil : new)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in fields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}

// MARK: - Small response shapes

nonisolated struct MeDTO: Decodable, Sendable {
    let email: String
    let role: String
}

/// Note the camelCase: this one object sits inside the otherwise snake_case
/// response from `POST /api/notices/:id/send`.
nonisolated struct PushDTO: Decodable, Sendable {
    let apnSent: Int
    let apnFailed: Int
    let fcmSent: Int
    let fcmFailed: Int

    var delivered: Int { apnSent + fcmSent }
    var failed: Int { apnFailed + fcmFailed }
}
