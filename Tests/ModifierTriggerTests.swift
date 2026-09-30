import AppKit
import Testing
@testable import Yap

struct ModifierTriggerTests {
    private func flags(_ independent: NSEvent.ModifierFlags, device: UInt) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: independent.rawValue | device)
    }

    @Test func tellsRightShiftFromLeft() {
        // With both down, letting go of Right Shift still reports `.shift`.
        let leftShiftOnly = flags(.shift, device: 0x0000_0002)
        #expect(!ModifierTrigger.rightShift.isDown(in: leftShiftOnly))
        #expect(ModifierTrigger.leftShift.isDown(in: leftShiftOnly))
        #expect(ModifierTrigger.rightShift.isDown(in: flags(.shift, device: 0x0000_0004)))
    }

    @Test func seesOtherModifiersAlreadyHeld() {
        let commandAndRightShift = flags([.command, .shift], device: 0x0000_0008 | 0x0000_0004)
        #expect(ModifierTrigger.rightShift.othersHeld(in: commandAndRightShift))
        #expect(!ModifierTrigger.rightShift.othersHeld(in: flags(.shift, device: 0x0000_0004)))
        #expect(ModifierTrigger.rightShift.othersHeld(in: flags(.shift, device: 0x0000_0002 | 0x0000_0004)))
    }

    @Test func fallsBackToTheSharedFlagWhenNoSideIsReported() {
        // Software KVMs post modifier changes without the device bits.
        #expect(ModifierTrigger.rightShift.isDown(in: .shift))
        #expect(!ModifierTrigger.rightShift.isDown(in: .command))
        #expect(!ModifierTrigger.rightShift.othersHeld(in: .shift))
    }

    @Test func fnHasNoSidesToTellApart() {
        #expect(ModifierTrigger.function.isDown(in: .function))
        #expect(!ModifierTrigger.function.othersHeld(in: .function))
        #expect(ModifierTrigger.rightOption.othersHeld(in: flags([.option, .function], device: 0x0000_0040)))
    }
}

struct CombinationScrollTests {
    @Test func wheelAndActiveTrackpadScrollsCount() {
        #expect(ModifierHotkeyMonitor.isDeliberateScroll(phase: [], momentumPhase: []))
        #expect(ModifierHotkeyMonitor.isDeliberateScroll(phase: .changed, momentumPhase: []))
    }

    @Test func momentumAndRestingFingersDoNot() {
        // A fling keeps scrolling for a second after the fingers leave.
        #expect(!ModifierHotkeyMonitor.isDeliberateScroll(phase: [], momentumPhase: .changed))
        #expect(!ModifierHotkeyMonitor.isDeliberateScroll(phase: .mayBegin, momentumPhase: []))
        #expect(!ModifierHotkeyMonitor.isDeliberateScroll(phase: .cancelled, momentumPhase: []))
    }
}
