import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.d, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyManager {
    private var pressHandler: ((Date) -> Void)?
    private var releaseHandler: ((Date) -> Void)?

    func onTrigger(pressed: @escaping (Date) -> Void, released: @escaping (Date) -> Void) {
        pressHandler = pressed
        releaseHandler = released
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            self?.pressHandler?(Self.lastEventTime(.keyDown))
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.releaseHandler?(Self.lastEventTime(.keyUp))
        }
    }

    /// Carbon hands over no event to read a timestamp from, so ask the event
    /// system when the key actually moved. The combined session state also
    /// counts keys that macro tools post, which the hardware state misses.
    private static func lastEventTime(_ type: CGEventType) -> Date {
        Date(timeIntervalSinceNow: -CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type))
    }
}
