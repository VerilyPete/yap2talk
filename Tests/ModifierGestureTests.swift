import Foundation
import Testing
@testable import Yap

struct ModifierGestureTests {
    private let pressedAt = Date()

    @Test func aQuickCleanPressIsATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false) == .tap)
    }

    @Test func aSlowPressIsNotATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(1), otherModifiersHeld: false) == nil)
    }

    @Test func aPressUsedInACombinationIsNotATap() {
        // Right Shift held to type a capital letter.
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.combined() == nil)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: false) == nil)
    }

    @Test func aPressWithAnotherModifierStillDownIsNotATap() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(0.2), otherModifiersHeld: true) == nil)
    }

    @Test func aCleanHoldStartsFromWhenTheKeyWentDown() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        #expect(gesture.holdElapsed() == .holdStarted(at: pressedAt))
        #expect(gesture.released(at: pressedAt.addingTimeInterval(3), otherModifiersHeld: false) == .holdEnded)
    }

    @Test func aCombinationDuringAHoldAbandonsIt() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.holdElapsed()
        #expect(gesture.combined() == .holdAbandoned)
        #expect(gesture.released(at: pressedAt.addingTimeInterval(3), otherModifiersHeld: false) == nil)
    }

    @Test func aCombinationBeforeTheHoldPreventsIt() {
        var gesture = ModifierGesture(holdsEnabled: true)
        gesture.pressed(at: pressedAt)
        _ = gesture.combined()
        #expect(gesture.holdElapsed() == nil)
    }

    @Test func holdsAreIgnoredWhenDisabled() {
        var gesture = ModifierGesture()
        gesture.pressed(at: pressedAt)
        #expect(gesture.holdElapsed() == nil)
    }

    @Test func aReleaseWithoutAPressIsNothing() {
        var gesture = ModifierGesture(holdsEnabled: true)
        #expect(gesture.released(at: pressedAt, otherModifiersHeld: false) == nil)
        #expect(gesture.holdElapsed() == nil)
    }
}
