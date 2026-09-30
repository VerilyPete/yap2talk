import Foundation
import Testing
@testable import Yap

@MainActor
final class FakeSession: DictationSessioning {
    var onLevel: ((Float) -> Void)?
    var onPartial: ((String) -> Void)?
    var textToReturn = "hello world"
    var startCalled = 0
    var stopCalled = 0
    var startGate: (() async -> Void)?
    var startError: Error?
    var stopGate: (() async -> Void)?
    var isRunning = false

    func start() async throws {
        startCalled += 1
        await startGate?()
        if let startError { throw startError }
        isRunning = true
    }
    func stop() async throws -> String {
        stopCalled += 1
        await stopGate?()
        isRunning = false
        return textToReturn
    }
}

@MainActor
final class FakeInjector: TextInjecting {
    var outcome: InjectionOutcome = .pasted
    var delivered: [String] = []
    var targetCaptures = 0

    func captureTarget() { targetCaptures += 1 }
    func deliver(_ text: String) async -> InjectionOutcome {
        delivered.append(text)
        return outcome
    }
}

@MainActor
final class FakeHistory: HistoryStoring {
    var saved: [String] = []
    func save(text: String, duration: Double?, device: String?) { saved.append(text) }
}

@MainActor
final class FakeHUD: HUDControlling {
    var phases: [HUDPhase] = []
    var shown = 0
    var hidden = 0
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    func show(device: String?) { shown += 1 }
    func setPhase(_ phase: HUDPhase) { phases.append(phase) }
    func setLevel(_ level: Float) {}
    func setPartial(_ text: String) {}
    func hide(after seconds: Double) { hidden += 1 }
    func setActions(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

final class FakeSounds: SoundPlaying {
    var stops = 0
    func playStart() {}
    func playStop() { stops += 1 }
}

@MainActor
final class FakeCleaner: TranscriptCleaning {
    var isAvailable = true
    var transform: (String) -> String = { $0 }
    var cleaned: [String] = []

    func process(_ text: String, cleanup: Bool, vocabulary: [String]) async -> String {
        cleaned.append(text)
        return transform(text)
    }
}

@MainActor
private func makeCoordinator(
    session: FakeSession? = nil,
    injector: FakeInjector? = nil,
    history: FakeHistory? = nil,
    hud: FakeHUD? = nil,
    sounds: FakeSounds? = nil,
    cleaner: FakeCleaner? = nil,
    cleanupEnabled: Bool = false,
    holdToTalkEnabled: Bool = true,
    vocabulary: [String] = []
) -> RecordingCoordinator {
    RecordingCoordinator(
        session: session ?? FakeSession(),
        injector: injector ?? FakeInjector(),
        history: history ?? FakeHistory(),
        hud: hud ?? FakeHUD(),
        sounds: sounds ?? FakeSounds(),
        cleaner: cleaner ?? FakeCleaner(),
        cleanupEnabled: { cleanupEnabled },
        holdToTalkEnabled: { holdToTalkEnabled },
        vocabulary: { vocabulary },
        deviceName: { "Test Mic" }
    )
}

@MainActor
struct RecordingCoordinatorTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    @Test func startsIdle() {
        let coordinator = makeCoordinator()
        #expect(coordinator.state == .idle)
    }

    @Test func toggleStartsRecording() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)
        await coordinator.toggle()
        #expect(coordinator.state == .recording)
        #expect(session.startCalled == 1)
    }

    @Test func capturesTargetAppBeforeShowingAnyUI() async {
        let injector = FakeInjector()
        let hud = FakeHUD()
        let coordinator = makeCoordinator(injector: injector, hud: hud)

        await coordinator.toggle()

        // Must happen on start, not at insert time, or the HUD could be mistaken
        // for the target.
        #expect(injector.targetCaptures == 1)
        #expect(hud.shown == 1)
    }

    @Test func fullCycleInsertsAndSaves() async {
        let session = FakeSession()
        let injector = FakeInjector()
        let history = FakeHistory()
        let coordinator = makeCoordinator(session: session, injector: injector, history: history)

        await coordinator.toggle()
        await coordinator.toggle()

        #expect(coordinator.state == .idle)
        #expect(session.stopCalled == 1)
        #expect(injector.delivered == ["hello world"])
        #expect(history.saved == ["hello world"])
        #expect(coordinator.lastOutcome == .pasted)
    }

    @Test(.timeLimit(.minutes(1))) func stopDuringStartWaitsForTheStartToFinish() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.toggle()

        // Stopping a half-built session would throw away what was said.
        #expect(session.stopCalled == 0)

        finishStart?.resume()
        await starting.value

        #expect(session.stopCalled == 1)
        #expect(injector.delivered == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func releasingAHeldTriggerFinishesTheDictation() async {
        let session = FakeSession()
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)
        let pressedAt = Date()

        await coordinator.triggerPressed(.shortcut, at: pressedAt)
        #expect(coordinator.state == .recording)
        await coordinator.triggerReleased(.shortcut, at: pressedAt.addingTimeInterval(2))

        #expect(session.stopCalled == 1)
        #expect(injector.delivered == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test func quickTapKeepsRecordingUntilTheNextPress() async {
        let session = FakeSession()
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)
        let pressedAt = Date()

        await coordinator.triggerPressed(.shortcut, at: pressedAt)
        await coordinator.triggerReleased(.shortcut, at: pressedAt.addingTimeInterval(0.1))
        #expect(coordinator.state == .recording)

        await coordinator.triggerPressed(.shortcut, at: pressedAt.addingTimeInterval(3))
        #expect(injector.delivered == ["hello world"])

        // The press already finished it; its release has nothing left to do.
        await coordinator.triggerReleased(.shortcut, at: pressedAt.addingTimeInterval(6))
        #expect(session.startCalled == 1)
        #expect(session.stopCalled == 1)
    }

    @Test func releaseAfterACancelledHoldDoesNothing() async {
        let session = FakeSession()
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)
        let pressedAt = Date()

        await coordinator.triggerPressed(.shortcut, at: pressedAt)
        await coordinator.cancel()
        await coordinator.triggerReleased(.shortcut, at: pressedAt.addingTimeInterval(2))

        #expect(session.stopCalled == 1)
        #expect(injector.delivered.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func releaseIsIgnoredWhenHoldToTalkIsOff() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session, holdToTalkEnabled: false)
        let pressedAt = Date()

        await coordinator.triggerPressed(.shortcut, at: pressedAt)
        await coordinator.triggerReleased(.shortcut, at: pressedAt.addingTimeInterval(2))

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 0)
    }

    @Test(.timeLimit(.minutes(1))) func cancelDuringStartDiscardsOnceTheStartFinishes() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.cancel()
        #expect(session.stopCalled == 0)

        finishStart?.resume()
        await starting.value

        #expect(session.stopCalled == 1)
        #expect(!session.isRunning)
        #expect(injector.delivered.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test(.timeLimit(.minutes(1))) func pressAfterCancelDuringStartDoesNotStartASecondSession() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = {
            guard finishStart == nil else { return }
            await withCheckedContinuation { finishStart = $0 }
        }
        let coordinator = makeCoordinator(session: session)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.cancel()
        await coordinator.toggle()
        finishStart?.resume()
        await starting.value

        #expect(session.startCalled == 1)
        #expect(coordinator.state == .idle)
    }

    @Test(.timeLimit(.minutes(1))) func deferredStopDoesNotCarryIntoTheNextDictation() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let coordinator = makeCoordinator(session: session)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.toggle()
        finishStart?.resume()
        await starting.value
        session.startGate = nil

        await coordinator.toggle()

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func stopPendingOnAFailedStartDoesNotCarryIntoTheNextDictation() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let coordinator = makeCoordinator(session: session)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.toggle()
        session.startError = CancellationError()
        finishStart?.resume()
        await starting.value
        #expect(coordinator.state == .idle)
        session.startGate = nil
        session.startError = nil

        await coordinator.toggle()

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 0)
    }

    @Test(.timeLimit(.minutes(1))) func releasingDuringTheStartFinishesOnceTheStartCompletes() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)

        let pressing = Task { await coordinator.triggerPressed(.shortcut, at: epoch) }
        while finishStart == nil { await Task.yield() }
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(2))
        #expect(session.stopCalled == 0)

        finishStart?.resume()
        await pressing.value

        #expect(session.stopCalled == 1)
        #expect(injector.delivered == ["hello world"])
        #expect(coordinator.state == .idle)
    }

    @Test(.timeLimit(.minutes(1))) func stopDuringStartReportsTheStopStraightAway() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let hud = FakeHUD()
        let sounds = FakeSounds()
        let coordinator = makeCoordinator(session: session, hud: hud, sounds: sounds)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.toggle()

        #expect(coordinator.state == .transcribing)
        #expect(hud.phases == [.listening, .transcribing])
        #expect(sounds.stops == 1)

        finishStart?.resume()
        await starting.value

        #expect(hud.phases == [.listening, .transcribing])
        #expect(sounds.stops == 1)
    }

    @Test(.timeLimit(.minutes(1))) func cancelDuringStartReportsTheCancelStraightAway() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let hud = FakeHUD()
        let sounds = FakeSounds()
        let coordinator = makeCoordinator(session: session, hud: hud, sounds: sounds)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.cancel()

        #expect(coordinator.state == .transcribing)
        #expect(hud.hidden == 1)
        #expect(sounds.stops == 1)

        finishStart?.resume()
        await starting.value
    }

    @Test(.timeLimit(.minutes(1))) func pressDuringADeferredCancelDoesNotRescueTheDictation() async {
        let session = FakeSession()
        var finishStart: CheckedContinuation<Void, Never>?
        session.startGate = { await withCheckedContinuation { finishStart = $0 } }
        let injector = FakeInjector()
        let history = FakeHistory()
        let coordinator = makeCoordinator(session: session, injector: injector, history: history)

        let starting = Task { await coordinator.toggle() }
        while finishStart == nil { await Task.yield() }
        await coordinator.cancel()
        await coordinator.triggerPressed(.shortcut, at: epoch)
        finishStart?.resume()
        await starting.value

        #expect(session.stopCalled == 1)
        #expect(injector.delivered.isEmpty)
        #expect(history.saved.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func releaseOfAHoldFinishedFromTheHUDLeavesTheNextDictationAlone() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.shortcut, at: epoch)
        await coordinator.toggle()
        #expect(coordinator.state == .idle)
        await coordinator.toggle()
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(2))

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 1)
    }

    @Test func escapeArmedInAFinishedDictationDoesNotCarryIntoTheNext() async {
        let hud = FakeHUD()
        let coordinator = makeCoordinator(hud: hud)

        await coordinator.toggle()
        coordinator.handleEscape()
        await coordinator.toggle()
        await coordinator.toggle()
        coordinator.handleEscape()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(coordinator.state == .recording)
        #expect(hud.phases.last == .confirmCancel)
    }

    @Test func escapeArmedInACancelledDictationDoesNotCarryIntoTheNext() async {
        let hud = FakeHUD()
        let coordinator = makeCoordinator(hud: hud)

        await coordinator.toggle()
        coordinator.handleEscape()
        await coordinator.cancel()
        await coordinator.toggle()
        coordinator.handleEscape()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(coordinator.state == .recording)
        #expect(hud.phases.last == .confirmCancel)
    }

    @Test func pressHeldForExactlyTheMinimumIsAHold() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.shortcut, at: epoch)
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(0.3))

        #expect(session.stopCalled == 1)
        #expect(coordinator.state == .idle)
    }

    @Test func pressReleasedJustShortOfTheMinimumIsATap() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.shortcut, at: epoch)
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(0.29))

        #expect(session.stopCalled == 0)
        #expect(coordinator.state == .recording)
    }

    @Test func releaseWithNoPressBehindItDoesNothing() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.toggle()
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(5))

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 0)
    }

    @Test func tapsReleaseIsSpentOnce() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.shortcut, at: epoch)
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(0.1))
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(2))

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 0)
    }

    @Test func releaseOfACancelledHoldLeavesTheNextDictationAlone() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.shortcut, at: epoch)
        await coordinator.cancel()
        await coordinator.toggle()
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(2))

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 1)
    }

    @Test(.timeLimit(.minutes(1))) func releaseOfAPressIgnoredWhileTranscribingLeavesTheNextDictationAlone() async {
        let session = FakeSession()
        var finishStop: CheckedContinuation<Void, Never>?
        let coordinator = makeCoordinator(session: session)

        await coordinator.toggle()
        session.stopGate = { await withCheckedContinuation { finishStop = $0 } }
        let stopping = Task { await coordinator.toggle() }
        while finishStop == nil { await Task.yield() }
        await coordinator.triggerPressed(.shortcut, at: epoch)
        finishStop?.resume()
        await stopping.value
        session.stopGate = nil

        await coordinator.toggle()
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(2))

        #expect(coordinator.state == .recording)
        #expect(session.stopCalled == 1)
    }

    @Test func releaseOfAnotherTriggerLeavesTheHoldAlone() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.functionKey, at: epoch)
        await coordinator.cancel()
        await coordinator.triggerPressed(.shortcut, at: epoch.addingTimeInterval(1))
        await coordinator.triggerReleased(.functionKey, at: epoch.addingTimeInterval(2))
        #expect(coordinator.state == .recording)

        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(3))
        #expect(coordinator.state == .idle)
    }

    @Test func failedStartDisarmsItsRelease() async {
        let session = FakeSession()
        session.startError = CancellationError()
        let coordinator = makeCoordinator(session: session)

        await coordinator.triggerPressed(.shortcut, at: epoch)
        session.startError = nil
        await coordinator.toggle()
        await coordinator.triggerReleased(.shortcut, at: epoch.addingTimeInterval(2))

        #expect(coordinator.state == .recording)
    }

    @Test func emptyTranscriptIsNotSavedOrInserted() async {
        let session = FakeSession()
        session.textToReturn = "   \n  "
        let injector = FakeInjector()
        let history = FakeHistory()
        let coordinator = makeCoordinator(session: session, injector: injector, history: history)

        await coordinator.toggle()
        await coordinator.toggle()

        #expect(history.saved.isEmpty)
        #expect(injector.delivered.isEmpty)
        #expect(coordinator.state == .idle)
    }

    @Test func nonEditableTargetLeavesTextOnClipboard() async {
        let session = FakeSession()
        let injector = FakeInjector()
        injector.outcome = .leftOnClipboard
        let history = FakeHistory()
        let coordinator = makeCoordinator(session: session, injector: injector, history: history)

        await coordinator.toggle()
        await coordinator.toggle()

        // Still saved to history even when it couldn't be pasted.
        #expect(history.saved == ["hello world"])
        #expect(coordinator.lastOutcome == .leftOnClipboard)
    }

    @Test func cancelDiscardsWithoutInsertingOrSaving() async {
        let session = FakeSession()
        let injector = FakeInjector()
        let history = FakeHistory()
        let hud = FakeHUD()
        let coordinator = makeCoordinator(session: session, injector: injector, history: history, hud: hud)

        await coordinator.toggle()
        await coordinator.cancel()

        #expect(coordinator.state == .idle)
        #expect(session.stopCalled == 1) // capture is still torn down
        #expect(hud.hidden == 1)
        #expect(injector.delivered.isEmpty)
        #expect(history.saved.isEmpty)
    }

    @Test func firstEscapeArmsCancelButKeepsRecording() async {
        let session = FakeSession()
        let hud = FakeHUD()
        let coordinator = makeCoordinator(session: session, hud: hud)

        await coordinator.toggle()
        coordinator.handleEscape()

        #expect(coordinator.state == .recording)
        #expect(hud.phases.contains(.confirmCancel))
        #expect(session.stopCalled == 0)
    }

    @Test func secondEscapeDiscardsTheDictation() async {
        let session = FakeSession()
        let injector = FakeInjector()
        let history = FakeHistory()
        let coordinator = makeCoordinator(session: session, injector: injector, history: history)

        await coordinator.toggle()
        coordinator.handleEscape()
        coordinator.handleEscape()

        // handleEscape spawns the cancel, so let it settle.
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(coordinator.state == .idle)
        #expect(injector.delivered.isEmpty)
        #expect(history.saved.isEmpty)
    }

    @Test func escapeIsIgnoredWhenNotRecording() async {
        let hud = FakeHUD()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.handleEscape()

        #expect(coordinator.state == .idle)
        #expect(!hud.phases.contains(.confirmCancel))
    }

    @Test func cancelIsIgnoredWhenNotRecording() async {
        let session = FakeSession()
        let coordinator = makeCoordinator(session: session)

        await coordinator.cancel()

        #expect(coordinator.state == .idle)
        #expect(session.stopCalled == 0)
    }

    @Test func cleanedTextIsInsertedAndSaved() async {
        let session = FakeSession()
        session.textToReturn = "um so hello world"
        let injector = FakeInjector()
        let history = FakeHistory()
        let hud = FakeHUD()
        let cleaner = FakeCleaner()
        cleaner.transform = { _ in "Hello world." }
        let coordinator = makeCoordinator(
            session: session, injector: injector, history: history, hud: hud,
            cleaner: cleaner, cleanupEnabled: true
        )

        await coordinator.toggle()
        await coordinator.toggle()

        // Fillers are stripped deterministically before the model sees the text.
        #expect(cleaner.cleaned == ["So hello world"])
        #expect(injector.delivered == ["Hello world."])
        #expect(history.saved == ["Hello world."])
        #expect(hud.phases.contains(.cleaning))
    }

    @Test func cleanupIsSkippedWhenDisabled() async {
        let injector = FakeInjector()
        let hud = FakeHUD()
        let cleaner = FakeCleaner()
        cleaner.transform = { _ in "should not appear" }
        let coordinator = makeCoordinator(
            injector: injector, hud: hud, cleaner: cleaner, cleanupEnabled: false
        )

        await coordinator.toggle()
        await coordinator.toggle()

        #expect(cleaner.cleaned.isEmpty)
        #expect(injector.delivered == ["hello world"])
        #expect(!hud.phases.contains(.cleaning))
    }

    @Test func cleanupIsSkippedWhenModelUnavailable() async {
        let injector = FakeInjector()
        let hud = FakeHUD()
        let cleaner = FakeCleaner()
        cleaner.isAvailable = false
        cleaner.transform = { _ in "should not appear" }
        let coordinator = makeCoordinator(
            injector: injector, hud: hud, cleaner: cleaner, cleanupEnabled: true
        )

        await coordinator.toggle()
        await coordinator.toggle()

        #expect(cleaner.cleaned.isEmpty)
        #expect(injector.delivered == ["hello world"])
        #expect(!hud.phases.contains(.cleaning))
    }

    @Test func trimsWhitespaceBeforeInserting() async {
        let session = FakeSession()
        session.textToReturn = "  padded text  "
        let injector = FakeInjector()
        let coordinator = makeCoordinator(session: session, injector: injector)

        await coordinator.toggle()
        await coordinator.toggle()

        #expect(injector.delivered == ["padded text"])
    }
}
