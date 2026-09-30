import AppKit
import Carbon.HIToolbox

/// Carbon hotkeys always require a real key alongside modifiers, so a bare
/// modifier can't be one — we watch `flagsChanged` for a clean tap instead.
enum ModifierTrigger: String, CaseIterable, Identifiable {
    case none
    case rightShift, leftShift
    case rightCommand, leftCommand
    case rightOption, leftOption
    case rightControl, leftControl
    case function

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Off"
        case .rightShift: return "Right ⇧ Shift"
        case .leftShift: return "Left ⇧ Shift"
        case .rightCommand: return "Right ⌘ Command"
        case .leftCommand: return "Left ⌘ Command"
        case .rightOption: return "Right ⌥ Option"
        case .leftOption: return "Left ⌥ Option"
        case .rightControl: return "Right ⌃ Control"
        case .leftControl: return "Left ⌃ Control"
        case .function: return "fn"
        }
    }

    /// `flagsChanged` reports which key changed — the only way to tell left from right.
    var keyCode: UInt16? {
        switch self {
        case .none: return nil
        case .leftShift: return UInt16(kVK_Shift)
        case .rightShift: return UInt16(kVK_RightShift)
        case .leftCommand: return UInt16(kVK_Command)
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .leftOption: return UInt16(kVK_Option)
        case .rightOption: return UInt16(kVK_RightOption)
        case .leftControl: return UInt16(kVK_Control)
        case .rightControl: return UInt16(kVK_RightControl)
        case .function: return UInt16(kVK_Function)
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .none: return nil
        case .leftShift, .rightShift: return .shift
        case .leftCommand, .rightCommand: return .command
        case .leftOption, .rightOption: return .option
        case .leftControl, .rightControl: return .control
        case .function: return .function
        }
    }
}

/// "Clean" means pressed and released on its own — so holding Right Shift to
/// type a capital letter never fires the trigger. A clean press released quickly
/// is a tap; one held past `maximumTapDuration` becomes a hold until release.
struct ModifierGesture {
    enum Outcome: Equatable {
        case tap
        case holdStarted(at: Date)
        case holdEnded
        case holdAbandoned
    }

    /// Longer than this and it was a hold, not a tap.
    static let maximumTapDuration: TimeInterval = 0.6

    var holdsEnabled = false

    private var pressedAt: Date?
    private var usedInCombination = false
    private var isHolding = false

    init(holdsEnabled: Bool = false) {
        self.holdsEnabled = holdsEnabled
    }

    mutating func pressed(at time: Date) {
        pressedAt = time
        usedInCombination = false
        isHolding = false
    }

    /// Another key, modifier or click while ours is down — that's a combo.
    mutating func combined() -> Outcome? {
        usedInCombination = true
        guard isHolding else { return nil }
        isHolding = false
        return .holdAbandoned
    }

    /// Called `maximumTapDuration` after a press, if it is still down.
    mutating func holdElapsed() -> Outcome? {
        guard holdsEnabled, let pressedAt, !usedInCombination else { return nil }
        isHolding = true
        return .holdStarted(at: pressedAt)
    }

    mutating func released(at time: Date, otherModifiersHeld: Bool) -> Outcome? {
        guard let pressedAt else { return nil }
        self.pressedAt = nil
        if isHolding {
            isHolding = false
            return .holdEnded
        }
        let heldFor = time.timeIntervalSince(pressedAt)
        guard !usedInCombination, heldFor < Self.maximumTapDuration, !otherModifiersHeld else { return nil }
        return .tap
    }
}

@MainActor
final class ModifierHotkeyMonitor {
    var trigger: ModifierTrigger = .none {
        didSet { reset() }
    }
    var holdsEnabled = false {
        didSet { reset() }
    }
    var onGesture: ((ModifierGesture.Outcome) -> Void)?

    private var monitors: [Any] = []
    private var gesture = ModifierGesture()
    private var holdTimer: Task<Void, Never>?

    func start() {
        stop()

        // Global monitors observe other apps; local ones cover Yap's own windows.
        addGlobal(matching: .flagsChanged) { [weak self] event in self?.handleFlags(event) }
        addGlobal(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.noteCombination()
        }
        addLocal(matching: .flagsChanged) { [weak self] event in self?.handleFlags(event) }
        addLocal(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.noteCombination()
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        reset()
    }

    private func addGlobal(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor in handler(event) }
        }) {
            monitors.append(monitor)
        }
    }

    private func addLocal(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            Task { @MainActor in handler(event) }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func reset() {
        holdTimer?.cancel()
        gesture = ModifierGesture(holdsEnabled: holdsEnabled)
    }

    private func noteCombination() {
        report(gesture.combined())
    }

    private func report(_ outcome: ModifierGesture.Outcome?) {
        if let outcome { onGesture?(outcome) }
    }

    private func handleFlags(_ event: NSEvent) {
        guard let keyCode = trigger.keyCode, let flag = trigger.flag else { return }

        guard event.keyCode == keyCode else {
            noteCombination()
            return
        }

        if event.modifierFlags.contains(flag) {
            gesture.pressed(at: Date())
            holdTimer?.cancel()
            holdTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ModifierGesture.maximumTapDuration))
                guard !Task.isCancelled, let self else { return }
                self.report(self.gesture.holdElapsed())
            }
            return
        }

        holdTimer?.cancel()
        let otherModifiersHeld = !event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .isEmpty
        report(gesture.released(at: Date(), otherModifiersHeld: otherModifiersHeld))
    }
}
