import Foundation
import Testing
@testable import Yap

struct ModifierGestureTests {
    private let pressedAt = Date(timeIntervalSinceReferenceDate: 0)

    @Test func quickCleanPressIsATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false) == .tap)
    }

    @Test func slowPressIsNotATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(1), otherModifiersHeld: false) == nil)
    }

    @Test func pressUsedInACombinationIsNotATap() {
        // Right Shift held to type a capital letter.
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(0.1)) == nil)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false) == nil)
    }

    @Test func pressWithAnotherModifierStillDownIsNotATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: true) == nil)
    }

    @Test func cleanHoldStartsFromWhenTheKeyWentDown() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        #expect(gesture.holdElapsed() == .holdStarted(at: pressedAt))
        #expect(gesture.released(at: pressedAt.addingTimeInterval(3), otherModifiersHeld: false) == .holdEnded(at: pressedAt.addingTimeInterval(3)))
    }

    @Test func combinationDuringAHoldAbandonsIt() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(1)) == .holdAbandoned)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(3), otherModifiersHeld: false) == nil)
    }

    @Test func combinationBeforeTheHoldPreventsIt() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.combined(at: pressedAt.addingTimeInterval(0.1))
        #expect(gesture.holdElapsed() == nil)
    }

    @Test func holdsAreIgnoredWhenDisabled() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.holdElapsed() == nil)
    }

    @Test func releaseWithoutAPressIsNothing() {
        var gesture = ModifierGesture(holdsEnabled: true)
        #expect(gesture.released(at: pressedAt, otherModifiersHeld: false) == nil)
        #expect(gesture.holdElapsed() == nil)
    }

    @Test func pressMadeWhileOtherInputIsHeldIsNeitherTapNorHold() {
        // Right Shift pressed with Command already down, or mid-drag.
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt, otherInputHeld: true)
        #expect(gesture.holdElapsed() == nil)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false) == nil)
    }

    @Test func combinationDoesNotSpoilTheNextPress() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        _ = gesture.combined(at: pressedAt.addingTimeInterval(0.1))
        _ = gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false)
        gesture.pressed(at: pressedAt.addingTimeInterval(5))
        #expect(gesture.released(at: pressedAt.addingTimeInterval(5.2), otherModifiersHeld: false) == .tap)
    }

    @Test func typingAfterAHoldEndsAbandonsNothing() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        _ = gesture.released(at: pressedAt.addingTimeInterval(3), otherModifiersHeld: false)
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(0.1)) == nil)
    }

    @Test func releaseIsReportedOnce() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false) == .tap)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.3), otherModifiersHeld: false) == nil)
    }

    @Test func freshPressAfterAMissedReleaseIsATap() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        gesture.pressed(at: pressedAt.addingTimeInterval(5))
        #expect(gesture.released(at: pressedAt.addingTimeInterval(5.2), otherModifiersHeld: false) == .tap)
    }

    @Test func pressReleasedAtTheTapLimitIsNotATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.6), otherModifiersHeld: false) == nil)
    }

    @Test func pressReleasedJustInsideTheTapLimitIsATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.59), otherModifiersHeld: false) == .tap)
    }

    @Test func keyEarlyInAHoldAbandonsItByDefault() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(1.59)) == .holdAbandoned)
    }

    @Test func keyLateInAHoldIsIgnoredByDefault() {
        // Clicking into a field 20 seconds in shouldn't throw the dictation away.
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(1.6)) == nil)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(20), otherModifiersHeld: false) == .holdEnded(at: pressedAt.addingTimeInterval(20)))
    }

    @Test func holdCanBeAbandonedAtAnyTime() {
        var gesture = ModifierGesture(holdsEnabled: true, interruption: .anyTime)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(20)) == .holdAbandoned)
    }

    @Test func holdCanIgnoreInterruptionsEntirely() {
        var gesture = ModifierGesture(holdsEnabled: true, interruption: .never)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(0.7)) == nil)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(3), otherModifiersHeld: false) == .holdEnded(at: pressedAt.addingTimeInterval(3)))
    }

    @Test func combinationBeforeTheHoldPreventsItWhateverTheSetting() {
        var gesture = ModifierGesture(holdsEnabled: true, interruption: .never)
        gesture.pressed(at: pressedAt)
        _ = gesture.combined(at: pressedAt.addingTimeInterval(0.1))
        #expect(gesture.holdElapsed() == nil)
    }

    @Test func keyFromBeforeTheHoldBeganAbandonsItWhateverTheSetting() {
        // Handled after the hold started, but typed before it.
        var gesture = ModifierGesture(holdsEnabled: true, interruption: .never)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined(at: pressedAt.addingTimeInterval(0.55)) == .holdAbandoned)
    }
}
