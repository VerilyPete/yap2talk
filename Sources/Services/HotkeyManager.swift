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
            self?.pressHandler?(Self.lastEvent(.keyDown))
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.releaseHandler?(Self.lastEvent(.keyUp))
        }
    }

    /// Carbon hands over no event to read a timestamp from, so ask the event
    /// system when the key actually moved.
    private static func lastEvent(_ type: CGEventType) -> Date {
        Date(timeIntervalSinceNow: -CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type))
    }
}
