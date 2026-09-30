import Foundation

extension Date {
    /// `NSEvent` timestamps count seconds from boot.
    init(systemUptime: TimeInterval) {
        self.init(timeIntervalSinceNow: systemUptime - ProcessInfo.processInfo.systemUptime)
    }

    /// Events at the HID tap carry raw `mach_absolute_time` ticks, which
    /// `NSEvent(cgEvent:)` would misread as nanoseconds. A stamp from the future
    /// can't be right, so it counts as now.
    init(machTime: UInt64) {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let now = mach_absolute_time()
        let ticks = now > machTime ? now - machTime : 0
        let seconds = Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e9
        self.init(timeIntervalSinceNow: -seconds)
    }
}
