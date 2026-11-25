import Foundation
import Testing
@testable import RateLimit

final class FakeClock: Clock, @unchecked Sendable {
    var time: TimeInterval = 1_000
    func now() -> TimeInterval { time }
}

@Suite struct TokenBucketTests {
    // @use-case:ratelimit.bucket.take#unit-tests.starts-full
    @Test func startsFull() {
        let bucket = TokenBucket(capacity: 5, refillPerSecond: 1, clock: FakeClock())
        #expect(bucket.available == 5)
    }
    // @use-case:end ratelimit.bucket.take#unit-tests.starts-full

    // @use-case:ratelimit.bucket.take#unit-tests.drains
    @Test func takingDrainsTokens() {
        let bucket = TokenBucket(capacity: 2, refillPerSecond: 1, clock: FakeClock())
        #expect(bucket.tryTake())
        #expect(bucket.tryTake())
        #expect(!bucket.tryTake())
    }
    // @use-case:end ratelimit.bucket.take#unit-tests.drains

    // @use-case:ratelimit.bucket.refill#unit-tests.caps-at-capacity
    @Test func refillsOverTimeUpToCapacity() {
        let clock = FakeClock()
        let bucket = TokenBucket(capacity: 3, refillPerSecond: 1, clock: clock)
        _ = bucket.tryTake(3)
        clock.time += 10
        #expect(bucket.available == 3)
    }
    // @use-case:end ratelimit.bucket.refill#unit-tests.caps-at-capacity

    // @use-case:ratelimit.bucket.refill#unit-tests.wait-time
    @Test(arguments: [(0.0, 0.0), (1.0, 2.0), (3.0, 6.0)])
    func waitTimeMatchesDeficit(taken: Double, expectedWait: Double) {
        let bucket = TokenBucket(capacity: 3, refillPerSecond: 0.5, clock: FakeClock())
        _ = bucket.tryTake(taken)
        #expect(bucket.waitTime(for: 3) == expectedWait)
    }
    // @use-case:end ratelimit.bucket.refill#unit-tests.wait-time

    @Test(.disabled("burst credits are planned"))
    func burstCreditsCarryOver() {}
}
