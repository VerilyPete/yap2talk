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
