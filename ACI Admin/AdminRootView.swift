//
//  AdminRootView.swift
//  ACI Admin
//
//  Root flow (sign in → PIN → console) and the tabbed main shell,
//  ported from admin-app.jsx. Click-through prototype: navigation is
//  live, actions show a toast and return — nothing talks to a backend.
//

import SwiftUI

// MARK: - Routes

enum AdminRoute: Hashable {
    case composeNotice(Notice?)
    case composeRule(RecurringRule?)
    case schedule(RecurringRule.ID)
    case composeEvent(ChurchEvent?)
    case review(TranslationItem.ID)
}

// MARK: - Root

struct AdminRootView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Phase { case signIn, pin, main }

    @State private var phase: Phase = .signIn
    @State private var store = AdminStore()

    var body: some View {
        Group {
            switch phase {
            case .signIn:
                AdSignInView {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .pin }
                }
                .transition(.opacity)
            case .pin:
                AdPinLockView {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .main }
                }
                .transition(.opacity)
            case .main:
                MainShellView()
                    .transition(.opacity)
            }
        }
        .environment(store)
        .environment(\.palette, Palette.forScheme(colorScheme))
    }
}

// MARK: - Main shell (tabs + navigation)

struct MainShellView: View {
    @Environment(\.palette) private var c
    @Environment(AdminStore.self) private var store

    @State private var tab: AdminTab = .today
    @State private var path: [AdminRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            rootScreen
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AdTabBar(selection: $tab, badge: store.pendingTotal)
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AdminRoute.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .tint(c.accent)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                AdToast(message: toast)
                    .padding(.bottom, path.isEmpty ? 84 : 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
    }

    @ViewBuilder
    private var rootScreen: some View {
        switch tab {
        case .today:
            AdHomeView(
                onReview: { lang in
                    store.reviewLanguage = lang
                    tab = .review
                },
                onCompose: { path.append(.composeNotice(nil)) },
                onQueue: { tab = .notices },
                onRecurring: { tab = .recurring },
                onEvents: { tab = .events }
            )
        case .notices:
            AdNoticesView { notice in
                path.append(.composeNotice(notice))
            }
        case .recurring:
            AdRecurringView(
                onOpen: { rule in path.append(.schedule(rule.id)) },
                onEdit: { rule in path.append(.composeRule(rule)) }
            )
        case .events:
            AdEventsView { event in
                path.append(.composeEvent(event))
            }
        case .review:
            AdReviewQueueView { item in
                path.append(.review(item.id))
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: AdminRoute) -> some View {
        switch route {
        case .composeNotice(let notice):
            AdComposeNoticeView(editing: notice)
        case .composeRule(let rule):
            AdRecurringComposeView(editing: rule)
        case .schedule(let id):
            AdScheduleView(ruleID: id)
        case .composeEvent(let event):
            AdComposeEventView(editing: event)
        case .review(let id):
            AdReviewItemView(itemID: id)
        }
    }
}

#Preview {
    AdminRootView()
}
