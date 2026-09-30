import Foundation
import Testing
@testable import Yap

struct EventTimeTests {
    @Test func placesAnEventTimestampOnTheWallClock() {
        let now = ProcessInfo.processInfo.systemUptime
        let secondAgo = Date(systemUptime: now - 1)
        #expect(abs(Date().timeIntervalSince(secondAgo) - 1) < 0.05)
    }
}

struct MachEventTimeTests {
    private func ticks(forSeconds seconds: Double) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return UInt64(seconds * 1e9 * Double(timebase.denom) / Double(timebase.numer))
    }

    @Test func placesAMachTimestampOnTheWallClock() {
        let secondAgo = Date(machTime: mach_absolute_time() - ticks(forSeconds: 1))
        #expect(abs(Date().timeIntervalSince(secondAgo) - 1) < 0.05)
    }

    @Test func treatsATimestampFromTheFutureAsNow() {
        let future = Date(machTime: mach_absolute_time() + ticks(forSeconds: 60))
        #expect(abs(Date().timeIntervalSince(future)) < 0.05)
    }
}
