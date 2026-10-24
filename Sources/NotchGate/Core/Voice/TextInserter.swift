import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Types a dictation into whatever has keyboard focus, in any app: the text goes on
/// the clipboard, NotchGate presses ⌘V, and the clipboard gets its old contents back.
@MainActor
enum TextInserter {
    enum Outcome: Equatable {
        case pasted
        /// Left on the clipboard instead of typed, and why.
        case copied(CopyReason)
    }

    enum CopyReason: Equatable {
        /// A password field is focused: dictation is never typed into one.
        case secureInput
        /// Without Accessibility, macOS drops the ⌘V NotchGate would press.
        case accessibilityOff
    }

    enum Plan: Equatable {
        /// Press ⌘V. Put the old clipboard back afterwards only when the text surely landed.
        case paste(restoreClipboard: Bool)
        case copy(CopyReason)
    }

    /// How long the target app gets to read the clipboard before it's restored.
    static let restoreDelay: Duration = .milliseconds(600)
    /// Tells clipboard managers to skip NotchGate's short-lived entry.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func insert(_ text: String) async -> Outcome {
        let pasteboard = NSPasteboard.general
        let focus = AXIsProcessTrusted() ? FocusedElement.current() : .other
        let plan = plan(trusted: AXIsProcessTrusted(), focus: focus, secureInput: IsSecureEventInputEnabled())
        Log.voice.notice("Inserting: \(String(describing: plan), privacy: .public), focus \(String(describing: focus), privacy: .public)")

        switch plan {
        case .copy(let reason):
            put(text, on: pasteboard, transient: false)
            return .copied(reason)
        case .paste(let restoreClipboard):
            let saved = snapshot(of: pasteboard)
            put(text, on: pasteboard, transient: restoreClipboard)
            let ours = pasteboard.changeCount
            pressPaste()
            try? await Task.sleep(for: restoreDelay)
            // Never undo something copied in the meantime.
            if restoreClipboard, pasteboard.changeCount == ours {
                restore(saved, to: pasteboard)
            }
            return .pasted
        }
    }

    /// Types straight into whatever has focus whenever macOS allows it, even when the app
    /// doesn't show its text field to Accessibility (Cursor, VS Code and other Electron
    /// apps often don't). Only a password field gets the clipboard instead.
    static func plan(trusted: Bool, focus: FocusedElement, secureInput: Bool) -> Plan {
        guard trusted else { return .copy(.accessibilityOff) }
        if focus == .secure { return .copy(.secureInput) }
        // Secure keyboard entry is on and the focused field can't be seen: assume a password.
        if secureInput, focus != .text { return .copy(.secureInput) }
        // Where the field couldn't be confirmed, the words also stay on the clipboard in
        // case the paste didn't land.
        return .paste(restoreClipboard: focus == .text)
    }

    // MARK: Clipboard

    private static func put(_ text: String, on pasteboard: NSPasteboard, transient: Bool) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if transient { pasteboard.setData(Data(), forType: transientType) }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    // MARK: ⌘V

    private static func pressPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let key = CGKeyCode(KeyboardLayout.keyCode(producing: "v") ?? UInt16(kVK_ANSI_V))
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// What has keyboard focus right now, according to Accessibility.
enum FocusedElement: Equatable {
    /// A text field, text view, search field or editable web content.
    case text
    /// A password field.
    case secure
    /// Something else, or an app that doesn't say (many Electron apps).
    case other
    /// Nothing has focus.
    case none

    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    static func current() -> FocusedElement {
        let system = AXUIElementCreateSystemWide()
        // An app that's hung shouldn't hold up the paste.
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        switch AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) {
        case .success: break
        case .noValue: return .none
        default: return .other
        }
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .other }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == kAXSecureTextFieldSubrole { return .secure }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let role = role as? String, textRoles.contains(role) { return .text }

        // Editable web content and custom text views expose a selection range.
        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success {
            return .text
        }
        return .other
    }
}

/// Finds the key that types a character in the user's keyboard layout, so ⌘V is
/// pressed correctly on Dvorak, AZERTY and friends.
enum KeyboardLayout {
    static func keyCode(producing character: Character) -> UInt16? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let target = String(character)

        return layoutData.withUnsafeBytes { raw -> UInt16? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in UInt16(0)..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
                )
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == target {
                    return code
                }
            }
            return nil
        }
    }
}
