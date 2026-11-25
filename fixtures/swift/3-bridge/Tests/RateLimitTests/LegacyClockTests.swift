import XCTest
@testable import RateLimit

final class LegacyClockTests: XCTestCase {
    func testSystemClockMovesForward() {
        let clock = SystemClock()
        let first = clock.now()
        XCTAssertGreaterThanOrEqual(clock.now(), first)
    }

    // @use-case:ratelimit.bucket.refill#unit-tests.no-refill
    func testZeroRefillNeverRecovers() {
        let bucket = TokenBucket(capacity: 1, refillPerSecond: 0, clock: FakeClock())
        _ = bucket.tryTake()
        XCTAssertEqual(bucket.waitTime(), .infinity)
    }
    // @use-case:end ratelimit.bucket.refill#unit-tests.no-refill
}
