import Foundation

extension Date {
    /// Event timestamps count from boot. Starting a dictation can hold the main
    /// thread long enough that a key-up is handled well after it happened, so
    /// holds are timed from the event, never from when its callback ran.
    init(systemUptime: TimeInterval) {
        self.init(timeIntervalSinceNow: systemUptime - ProcessInfo.processInfo.systemUptime)
    }
}
