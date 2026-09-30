import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.d, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyManager {
    private var pressHandler: (() -> Void)?
    private var releaseHandler: (() -> Void)?

    func onTrigger(pressed: @escaping () -> Void, released: @escaping () -> Void) {
        pressHandler = pressed
        releaseHandler = released
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            self?.pressHandler?()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.releaseHandler?()
        }
    }
}
