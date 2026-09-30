import CoreGraphics
import Carbon.HIToolbox
import Testing
@testable import Yap

struct FunctionKeyTriggerTests {
    @Test func firesOnBareMatchingKey() {
        #expect(FunctionKeyTrigger.shouldFire(
            trigger: .f6, keyCode: Int64(kVK_F6), flags: [], isRepeat: false
        ))
    }

    @Test func dictationMatchesBothItsKeycodes() {
        #expect(FunctionKeyTrigger.shouldFire(
            trigger: .dictation, keyCode: Int64(kVK_F5), flags: [], isRepeat: false
        ))
        #expect(FunctionKeyTrigger.shouldFire(
            trigger: .dictation, keyCode: 176, flags: [], isRepeat: false
        ))
    }

    @Test func ignoresOtherKeys() {
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .dictation, keyCode: Int64(kVK_F6), flags: [], isRepeat: false
        ))
    }

    @Test func passesThroughModifierCombos() {
        // ⌘F5 is VoiceOver — a bound dictation key must not eat it.
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .dictation, keyCode: Int64(kVK_F5), flags: .maskCommand, isRepeat: false
        ))
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .f1, keyCode: Int64(kVK_F1), flags: .maskShift, isRepeat: false
        ))
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .f1, keyCode: Int64(kVK_F1), flags: .maskAlternate, isRepeat: false
        ))
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .f1, keyCode: Int64(kVK_F1), flags: .maskControl, isRepeat: false
        ))
    }

    @Test func allowsTheFnFlag() {
        // Holding fn is how F-keys are typed at all when the row is in media
        // mode; it must not disqualify the press.
        #expect(FunctionKeyTrigger.shouldFire(
            trigger: .f6, keyCode: Int64(kVK_F6), flags: .maskSecondaryFn, isRepeat: false
        ))
    }

    @Test func ignoresAutoRepeat() {
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .f6, keyCode: Int64(kVK_F6), flags: [], isRepeat: true
        ))
    }

    @Test func offNeverFires() {
        #expect(!FunctionKeyTrigger.shouldFire(
            trigger: .none, keyCode: Int64(kVK_F5), flags: [], isRepeat: false
        ))
    }

    @Test func pressingTheTriggerIsAPress() {
        #expect(FunctionKeyTrigger.response(
            trigger: .dictation, isKeyDown: true, keyCode: Int64(kVK_F5), flags: [],
            isRepeat: false, heldKeyCode: nil
        ) == .press)
    }

    @Test func releasingTheHeldKeyIsTheRelease() {
        #expect(FunctionKeyTrigger.response(
            trigger: .dictation, isKeyDown: false, keyCode: Int64(kVK_F5), flags: [],
            isRepeat: false, heldKeyCode: Int64(kVK_F5)
        ) == .release)
    }

    @Test func swallowsAutoRepeatsOfTheHeldKey() {
        // Passed through, a repeating F5 would start macOS dictation mid-hold.
        #expect(FunctionKeyTrigger.response(
            trigger: .dictation, isKeyDown: true, keyCode: Int64(kVK_F5), flags: [],
            isRepeat: true, heldKeyCode: Int64(kVK_F5)
        ) == .swallow)
    }

    @Test func freshPressOfTheHeldKeyIsAPress() {
        // A key-up the tap never saw must not wedge the trigger.
        #expect(FunctionKeyTrigger.response(
            trigger: .dictation, isKeyDown: true, keyCode: Int64(kVK_F5), flags: [],
            isRepeat: false, heldKeyCode: Int64(kVK_F5)
        ) == .press)
    }

    @Test func passesThroughKeysYapIsNotHolding() {
        #expect(FunctionKeyTrigger.response(
            trigger: .f6, isKeyDown: false, keyCode: Int64(kVK_F6), flags: [],
            isRepeat: false, heldKeyCode: nil
        ) == .passThrough)
        #expect(FunctionKeyTrigger.response(
            trigger: .f6, isKeyDown: true, keyCode: Int64(kVK_F6), flags: [],
            isRepeat: true, heldKeyCode: nil
        ) == .passThrough)
        #expect(FunctionKeyTrigger.response(
            trigger: .f6, isKeyDown: true, keyCode: Int64(kVK_F7), flags: [],
            isRepeat: false, heldKeyCode: Int64(kVK_F6)
        ) == .passThrough)
    }

    @Test func anotherKeysKeyUpDuringAHoldIsNotTheRelease() {
        #expect(FunctionKeyTrigger.response(
            trigger: .f6, isKeyDown: false, keyCode: Int64(kVK_F7), flags: [],
            isRepeat: false, heldKeyCode: Int64(kVK_F6)
        ) == .passThrough)
    }

    @Test func anotherKeysRepeatsDuringAHoldPassThrough() {
        #expect(FunctionKeyTrigger.response(
            trigger: .f6, isKeyDown: true, keyCode: Int64(kVK_F7), flags: [],
            isRepeat: true, heldKeyCode: Int64(kVK_F6)
        ) == .passThrough)
    }

    @Test func releasingTheHeldKeyWithAModifierDownIsStillTheRelease() {
        #expect(FunctionKeyTrigger.response(
            trigger: .dictation, isKeyDown: false, keyCode: Int64(kVK_F5), flags: .maskCommand,
            isRepeat: false, heldKeyCode: Int64(kVK_F5)
        ) == .release)
    }

    @Test func modifierComboOfTheTriggerKeyPassesThrough() {
        // ⌘F5 is VoiceOver; the tap must hand it on, not swallow it as a press.
        #expect(FunctionKeyTrigger.response(
            trigger: .dictation, isKeyDown: true, keyCode: Int64(kVK_F5), flags: .maskCommand,
            isRepeat: false, heldKeyCode: nil
        ) == .passThrough)
    }
}
