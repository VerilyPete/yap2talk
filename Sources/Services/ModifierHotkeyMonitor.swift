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

    /// `flagsChanged` reports which key changed.
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

    /// `NX_DEVICE…KEYMASK` bits. The shared `.shift`-style flag can't tell the
    /// two sides apart: with both Shifts down, letting go of one still reports
    /// `.shift`. fn has only the one key, so its own flag serves.
    var deviceMask: UInt {
        switch self {
        case .none: return 0
        case .leftControl: return 0x0000_0001
        case .leftShift: return 0x0000_0002
        case .rightShift: return 0x0000_0004
        case .leftCommand: return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        case .function: return NSEvent.ModifierFlags.function.rawValue
        }
    }

    /// Some software KVMs post modifier changes without any device bits; for
    /// those, the shared flag is all there is to go on.
    private var flag: NSEvent.ModifierFlags {
        switch self {
        case .none: return []
        case .leftShift, .rightShift: return .shift
        case .leftCommand, .rightCommand: return .command
        case .leftOption, .rightOption: return .option
        case .leftControl, .rightControl: return .control
        case .function: return .function
        }
    }

    private static let allDeviceMasks = allCases.reduce(0) { $0 | $1.deviceMask }
    /// fn's mask is its shared flag, so it says nothing about whether the
    /// event reports sides.
    private static let sideMasks = allDeviceMasks & ~ModifierTrigger.function.deviceMask

    func isDown(in flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.rawValue & Self.sideMasks != 0 else {
            return self != .none && flags.contains(flag)
        }
        return flags.rawValue & deviceMask != 0
    }

    func othersHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.rawValue & Self.sideMasks != 0 else {
            return !flags.intersection([.shift, .control, .option, .command, .function]).subtracting(flag).isEmpty
        }
        return flags.rawValue & (Self.allDeviceMasks & ~deviceMask) != 0
    }
}

/// What another key, click or scroll does to a modifier hold that has already
/// started recording: it may mean the hold was a shortcut after all, or just a
/// click into the field being dictated into.
enum HoldInterruption: String, CaseIterable, Identifiable {
    case earlyOnly, anyTime, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earlyOnly: return "In the first second"
        case .anyTime: return "Any time"
        case .never: return "Never"
        }
    }
}

/// How long a modifier must be held, alone, before recording starts. Shorter
/// starts sooner, but a tap then has to be quicker too, and holding Shift a
/// moment before a capital letter starts (and abandons) more dictations. None
/// is below the coordinator's minimum hold, since holds are timed from key-down.
enum HoldDelay: String, CaseIterable, Identifiable {
    case quick, medium, standard

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .quick: return 0.3
        case .medium: return 0.45
        case .standard: return ModifierGesture.maximumTapDuration
        }
    }

    var title: String {
        switch self {
        case .quick: return "0.3 seconds"
        case .medium: return "0.45 seconds"
        case .standard: return "0.6 seconds"
        }
    }
}

/// "Clean" means pressed and released on its own — so holding Right Shift to
/// type a capital letter never fires the trigger. A clean press released quickly
/// is a tap; one held past `holdDelay` becomes a hold until release.
/// `interruption` decides whether a combo that follows abandons the hold.
struct ModifierGesture {
    enum Outcome: Equatable {
        case tap
        case holdStarted(at: Date)
        case holdEnded(at: Date)
        case holdAbandoned
    }

    /// Longer than this and it was a hold, not a tap. With holds on, the hold
    /// delay takes over, so a press is always one or the other.
    static let maximumTapDuration: TimeInterval = 0.6

    /// How long after recording starts `.earlyOnly` still treats another key
    /// as a sign the hold was a shortcut.
    static let interruptionWindow: TimeInterval = 1

    let holdsEnabled: Bool
    var interruption: HoldInterruption
    var holdDelay: HoldDelay

    private var pressedAt: Date?
    private var usedInCombination = false
    private var isHoldingToTalk = false

    init(holdsEnabled: Bool = false, interruption: HoldInterruption = .earlyOnly, holdDelay: HoldDelay = .standard) {
        self.holdsEnabled = holdsEnabled
        self.interruption = interruption
        self.holdDelay = holdDelay
    }

    private var tapWindow: TimeInterval {
        holdsEnabled ? holdDelay.seconds : Self.maximumTapDuration
    }

    /// A press made while another modifier or a mouse button is already down
    /// is part of that combo from the start.
    mutating func pressed(at time: Date, otherInputHeld: Bool = false) {
        pressedAt = time
        usedInCombination = otherInputHeld
        isHoldingToTalk = false
    }

    /// Another key, modifier, click, drag, scroll or gesture while ours is
    /// down — that's a combo.
    mutating func combined(at time: Date) -> Outcome? {
        usedInCombination = true
        guard isHoldingToTalk, let pressedAt else { return nil }
        let recordingFor = time.timeIntervalSince(pressedAt) - holdDelay.seconds
        // Input from before recording began was a shortcut, whatever the setting.
        switch interruption {
        case .never where recordingFor >= 0: return nil
        case .earlyOnly where recordingFor >= Self.interruptionWindow: return nil
        case .never, .earlyOnly, .anyTime: break
        }
        isHoldingToTalk = false
        return .holdAbandoned
    }

    /// Called `holdDelay` after a press, if it is still down.
    mutating func holdElapsed() -> Outcome? {
        guard holdsEnabled, let pressedAt, !usedInCombination else { return nil }
        isHoldingToTalk = true
        return .holdStarted(at: pressedAt)
    }

    mutating func released(at time: Date, otherModifiersHeld: Bool) -> Outcome? {
        guard let pressedAt else { return nil }
        self.pressedAt = nil
        if isHoldingToTalk {
            isHoldingToTalk = false
            return .holdEnded(at: time)
        }
        let heldFor = time.timeIntervalSince(pressedAt)
        guard !usedInCombination, heldFor < tapWindow, !otherModifiersHeld else { return nil }
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
    var holdInterruption: HoldInterruption = .earlyOnly {
        didSet { gesture.interruption = holdInterruption }
    }
    var holdDelay: HoldDelay = .standard {
        didSet { gesture.holdDelay = holdDelay }
    }
    var onGesture: ((ModifierGesture.Outcome) -> Void)?

    /// Anything that makes a held modifier part of a shortcut: keys, clicks,
    /// drags, ⇧-scroll, ⌃-scroll zoom, trackpad gestures.
    private static let combinationEvents: NSEvent.EventTypeMask = [
        .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .scrollWheel, .magnify, .rotate, .swipe, .smartMagnify,
    ]

    private var monitors: [Any] = []
    private var gesture = ModifierGesture()
    private var holdTimer: Task<Void, Never>?

    func start() {
        stop()

        // Global monitors observe other apps; local ones cover Yap's own windows.
        addGlobal(matching: .flagsChanged) { [weak self] event in self?.handleFlags(event) }
        addGlobal(matching: Self.combinationEvents) { [weak self] event in
            self?.noteCombination(event)
        }
        addLocal(matching: .flagsChanged) { [weak self] event in self?.handleFlags(event) }
        addLocal(matching: Self.combinationEvents) { [weak self] event in
            self?.noteCombination(event)
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
        gesture = ModifierGesture(holdsEnabled: holdsEnabled, interruption: holdInterruption, holdDelay: holdDelay)
    }

    private func noteCombination(_ event: NSEvent) {
        if event.type == .scrollWheel,
           !Self.isDeliberateScroll(phase: event.phase, momentumPhase: event.momentumPhase) {
            return
        }
        report(gesture.combined(at: Date(systemUptime: event.timestamp)))
    }

    /// Only a scroll the user is making counts. A fling keeps sending momentum
    /// for a second after the fingers lift, and resting two fingers on the
    /// trackpad sends a scroll that may never begin.
    nonisolated static func isDeliberateScroll(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Bool {
        momentumPhase.isEmpty && !phase.contains(.mayBegin) && !phase.contains(.cancelled)
    }

    private func report(_ outcome: ModifierGesture.Outcome?) {
        if let outcome { onGesture?(outcome) }
    }

    private func handleFlags(_ event: NSEvent) {
        guard let keyCode = trigger.keyCode else { return }

        guard event.keyCode == keyCode else {
            noteCombination(event)
            return
        }

        let time = Date(systemUptime: event.timestamp)
        if trigger.isDown(in: event.modifierFlags) {
            let otherInputHeld = trigger.othersHeld(in: event.modifierFlags) || NSEvent.pressedMouseButtons != 0
            gesture.pressed(at: time, otherInputHeld: otherInputHeld)
            holdTimer?.cancel()
            guard holdsEnabled else { return }
            let wait = holdDelay.seconds - Date().timeIntervalSince(time)
            holdTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(wait, 0)))
                guard !Task.isCancelled, let self else { return }
                self.report(self.gesture.holdElapsed())
            }
            return
        }

        holdTimer?.cancel()
        let otherModifiersHeld = !event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .isEmpty
        report(gesture.released(at: time, otherModifiersHeld: otherModifiersHeld))
    }
}
