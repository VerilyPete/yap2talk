import Foundation
import Observation

// System dependencies are injected as protocols so this logic can be unit-tested with fakes.
@MainActor
@Observable
final class RecordingCoordinator {
    enum State: Equatable {
        case idle, recording, transcribing, inserting
    }

    private(set) var state: State = .idle
    private(set) var lastOutcome: InjectionOutcome?

    private let session: DictationSessioning
    private let injector: TextInjecting
    private let history: HistoryStoring
    private let hud: HUDControlling
    private let sounds: SoundPlaying
    private let cleaner: TranscriptCleaning
    private let cleanupEnabled: () -> Bool
    private let holdToTalkEnabled: () -> Bool
    private let vocabulary: () -> [String]
    private let deviceName: () -> String?

    private var startedAt: Date?

    // A stop that arrives while the session is still starting waits for it; tearing down a half-built session would leave the microphone running unseen.
    private var isStarting = false
    private var stopWhenStarted = false

    // Hold to talk: a press that starts a dictation and is held past this finishes it on release. A quicker tap leaves it recording until the next press, as before.
    private var heldSince: Date?
    private let minimumHoldDuration: TimeInterval = 0.3

    private var cancelArmed = false
    private var cancelArmTask: Task<Void, Never>?
    private let cancelArmWindow: Duration = .milliseconds(2500)

    init(
        session: DictationSessioning,
        injector: TextInjecting,
        history: HistoryStoring,
        hud: HUDControlling,
        sounds: SoundPlaying,
        cleaner: TranscriptCleaning,
        cleanupEnabled: @escaping () -> Bool,
        holdToTalkEnabled: @escaping () -> Bool,
        vocabulary: @escaping () -> [String],
        deviceName: @escaping () -> String?
    ) {
        self.session = session
        self.injector = injector
        self.history = history
        self.hud = hud
        self.sounds = sounds
        self.cleaner = cleaner
        self.cleanupEnabled = cleanupEnabled
        self.holdToTalkEnabled = holdToTalkEnabled
        self.vocabulary = vocabulary
        self.deviceName = deviceName

        session.onLevel = { [weak self] level in self?.hud.setLevel(level) }
        session.onPartial = { [weak self] text in self?.hud.setPartial(text) }

        hud.setActions(
            onConfirm: { [weak self] in Task { await self?.toggle() } },
            onCancel: { [weak self] in Task { await self?.cancel() } }
        )
    }

    func cancel() async {
        guard state == .recording else { return }
        disarmCancel()
        state = .transcribing
        sounds.playStop()
        hud.hide(after: 0)
        _ = try? await session.stop()
        state = .idle
    }

    // Two-step cancel: first press arms it, a second press within the window discards. Prevents a stray Escape (dismissing a menu, say) from destroying a dictation in progress.
    func handleEscape() {
        guard state == .recording else { return }

        if cancelArmed {
            disarmCancel()
            Task { await cancel() }
            return
        }

        cancelArmed = true
        hud.setPhase(.confirmCancel)
        cancelArmTask = Task { [weak self] in
            try? await Task.sleep(for: self?.cancelArmWindow ?? .milliseconds(2500))
            guard !Task.isCancelled, let self, self.cancelArmed else { return }
            self.cancelArmed = false
            if self.state == .recording { self.hud.setPhase(.listening) }
        }
    }

    private func disarmCancel() {
        cancelArmTask?.cancel()
        cancelArmTask = nil
        cancelArmed = false
    }

    func toggle() async {
        switch state {
        case .idle:
            await startRecording()
        case .recording:
            await stopRecording()
        case .transcribing, .inserting:
            break
        }
    }

    func triggerPressed(at time: Date = Date()) async {
        heldSince = time
        await toggle()
    }

    func triggerReleased(at time: Date = Date()) async {
        guard let heldSince else { return }
        self.heldSince = nil
        guard holdToTalkEnabled(),
              state == .recording,
              time.timeIntervalSince(heldSince) >= minimumHoldDuration
        else { return }
        await stopRecording()
    }

    private func startRecording() async {
        // Capture the target app BEFORE any Yap UI appears, so the paste goes to where the user actually was.
        injector.captureTarget()

        state = .recording
        startedAt = Date()
        sounds.playStart()
        hud.show(device: deviceName())
        hud.setPhase(.listening)

        isStarting = true
        do {
            try await session.start()
            isStarting = false
        } catch {
            isStarting = false
            stopWhenStarted = false
            NSLog("Yap: failed to start recording: \(error.localizedDescription)")
            hud.hide(after: 0)
            state = .idle
            return
        }

        if stopWhenStarted {
            stopWhenStarted = false
            await stopRecording()
        }
    }

    private func stopRecording() async {
        guard !isStarting else {
            stopWhenStarted = true
            return
        }
        disarmCancel()
        state = .transcribing
        sounds.playStop()
        hud.setPhase(.transcribing)

        do {
            let raw = try await session.stop()
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                hud.hide(after: 0)
                state = .idle
                return
            }

            // Deterministic passes first: instant, on device, no model needed.
            text = FillerRemoval.strip(text)
            let terms = vocabulary()
            if !terms.isEmpty {
                text = DictionaryCorrection.correctFirstLetterMisses(in: text, terms: terms)
            }

            // Removing fillers can empty a transcript that was only "um uh".
            guard !text.isEmpty else {
                hud.hide(after: 0)
                state = .idle
                return
            }

            // Cleanup also applies the dictionary to messier mis-hearings. If you
            // want your transcript cleaned, you want your names right too, so the
            // two ride the same setting and run in one pass.
            if cleanupEnabled(), cleaner.isAvailable {
                hud.setPhase(.cleaning)
                text = await cleaner.process(text, cleanup: true, vocabulary: terms)
            }

            state = .inserting
            let outcome = await injector.deliver(text)
            lastOutcome = outcome
            if case .blockedBySecureInput(let holder) = outcome {
                NSLog("Yap: paste blocked by secure input held by \(holder ?? "another app"); text left on clipboard")
            }

            let duration = startedAt.map { Date().timeIntervalSince($0) }
            history.save(text: text, duration: duration, device: deviceName())

            hud.hide(after: 0)
        } catch {
            NSLog("Yap: failed to finish recording: \(error.localizedDescription)")
            hud.hide(after: 0)
        }
        state = .idle
    }
}
