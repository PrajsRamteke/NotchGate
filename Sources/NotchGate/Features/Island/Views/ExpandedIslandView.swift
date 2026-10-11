import NotchGateKit
import SwiftUI

/// The expanded card area beneath the notch strip. Routes each request kind
/// to its feature card and cross-fades between queued requests.
struct ExpandedIslandView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let request = model.store.current {
                RequestHeaderView(
                    request: request,
                    pendingCount: model.store.pendingCount,
                    onOpenTerminal: { model.openTerminal(for: request.session) },
                    onCollapse: model.collapse
                )
                card(for: request)
                    .id(request.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else if let notice = model.store.notice {
                NoticeCardView(
                    notice: notice,
                    onOpenTerminal: {
                        model.openTerminal(for: notice.session)
                        model.dismissNotice()
                    },
                    onDismiss: model.dismissNotice
                )
            } else {
                ActivityPanelView(
                    tracker: model.activity,
                    settings: model.settings,
                    onOpen: model.openTerminal(for:),
                    onSetAutoAllow: model.setAutoAllow
                )
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Metrics.contentPadding)
        .padding(.top, 10)
        .padding(.bottom, Theme.Metrics.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func card(for request: ClaudeRequest) -> some View {
        let respond: (BridgeDecision) -> Void = { model.respond($0) }
        switch request.kind {
        case .permission(let permission):
            PermissionCardView(
                permission: permission,
                isAutoAllowOn: model.settings.autoAllowPermissions,
                onSetAutoAllow: model.setAutoAllow,
                onFocus: model.requestKeyFocus,
                onDecision: respond
            )
        case .question(let prompt):
            QuestionCardView(prompt: prompt, onFocus: model.requestKeyFocus, onDecision: respond)
        case .plan(let plan):
            PlanCardView(plan: plan, onFocus: model.requestKeyFocus, onDecision: respond)
        case .elicitation(let prompt):
            ElicitationCardView(prompt: prompt, onFocus: model.requestKeyFocus, onDecision: respond)
        case .completion(let prompt):
            CompletionCardView(
                prompt: prompt,
                receivedAt: request.receivedAt,
                expiresAt: request.expiresAt,
                onFocus: model.requestKeyFocus,
                onDecision: respond
            )
        }
    }
}
