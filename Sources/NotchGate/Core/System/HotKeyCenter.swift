import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts via Carbon `RegisterEventHotKey`.
///
/// Unlike `NSEvent` global monitors, this needs no Accessibility permission,
/// and the key press is consumed instead of leaking into the frontmost app.
@MainActor
final class HotKeyCenter {
    enum Action: UInt32, CaseIterable {
        case primary = 1   // ⌃⌥⏎  Allow / Approve / Submit
        case reject = 2    // ⌃⌥⌫  Deny / Reject / Dismiss
        case toggle = 3    // ⌃⌥Space  Expand / collapse the island

        var keyCode: UInt32 {
            switch self {
            case .primary: return UInt32(kVK_Return)
            case .reject: return UInt32(kVK_Delete)
            case .toggle: return UInt32(kVK_Space)
            }
        }

        static let modifiers = UInt32(controlKey | optionKey)
    }

    private static let signature: OSType = 0x4E47_4154 // "NGAT"
    private var hotKeys: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private let onAction: @MainActor (Action) -> Void

    init(onAction: @escaping @MainActor (Action) -> Void) {
        self.onAction = onAction
    }

    func register() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { center.dispatch(id.id) }
            return noErr
        }, 1, &spec, context, &handlerRef)

        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            RegisterEventHotKey(action.keyCode, Action.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if let ref { hotKeys.append(ref) }
        }
    }

    func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func dispatch(_ rawID: UInt32) {
        guard let action = Action(rawValue: rawID) else { return }
        onAction(action)
    }
}
