//
//  AdLoadState.swift
//  ACI Admin
//
//  One renderer for "loading / failed / here it is", so no screen has to grow its
//  own spinner or error handling.
//

import SwiftUI

struct AdLoadState<Value: Sendable, Content: View>: View {
    @Environment(\.palette) private var c

    private let state: Loadable<Value>
    private let retry: () async -> Void
    private let content: (Value) -> Content

    init(_ state: Loadable<Value>,
         retry: @escaping () async -> Void,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.state = state
        self.retry = retry
        self.content = content
    }

    var body: some View {
        if let value = state.value {
            // Something to show. A failed *refresh* keeps the old data and explains
            // itself in a strip rather than throwing the screen away.
            VStack(alignment: .leading, spacing: 0) {
                if let error = state.error {
                    AdErrorStrip(error: error, retry: retry)
                }
                content(value)
            }
        } else if let error = state.error {
            AdErrorState(error: error, retry: retry)
        } else {
            AdLoadingState()
        }
    }
}

struct AdLoadingState: View {
    @Environment(\.palette) private var c

    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(c.accent)
            Spacer()
        }
        .padding(.vertical, 64)
    }
}

struct AdErrorState: View {
    @Environment(\.palette) private var c
    let error: APIError
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(c.fgMuted)

            Text(error == .offline ? "You're offline" : "That didn't load")
                .font(AdFont.sans(16, weight: .semibold))
                .foregroundStyle(c.fg)

            Text(error.message)
                .font(AdFont.sans(13))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(c.fgMuted)
                .padding(.horizontal, 36)

            AdButton(label: "Try again", variant: .secondary, small: true) {
                Task { await retry() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}

/// Shown above content we already had when a refresh fails.
struct AdErrorStrip: View {
    @Environment(\.palette) private var c
    let error: APIError
    let retry: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.destructive)
            Text(error.message)
                .font(AdFont.sans(12))
                .foregroundStyle(c.fg)
            Spacer(minLength: 0)
            Button("Retry") { Task { await retry() } }
                .font(AdFont.sans(12, weight: .bold))
                .foregroundStyle(c.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(c.surfaceRaised, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.dangerEdge))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

/// Against a fresh server the lists are genuinely empty, and a blank screen reads as
/// a bug rather than as "nothing here yet".
struct AdEmptyState: View {
    @Environment(\.palette) private var c
    let icon: String
    let title: String
    var message: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(c.fgMuted)

            Text(title)
                .font(AdFont.sans(15, weight: .semibold))
                .foregroundStyle(c.fg)

            if let message {
                Text(message)
                    .font(AdFont.sans(12.5))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(c.fgMuted)
                    .padding(.horizontal, 40)
            }

            if let actionLabel, let action {
                AdButton(label: actionLabel, variant: .secondary, small: true, action: action)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}
