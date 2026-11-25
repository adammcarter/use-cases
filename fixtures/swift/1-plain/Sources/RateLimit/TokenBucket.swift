import Foundation

public protocol Clock: Sendable {
    func now() -> TimeInterval
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> TimeInterval { Date().timeIntervalSince1970 }
}

public final class TokenBucket {
    public let capacity: Double
    public let refillPerSecond: Double
    private var tokens: Double
    private var lastRefill: TimeInterval
    private let clock: Clock

    public init(capacity: Double, refillPerSecond: Double, clock: Clock = SystemClock()) {
        precondition(capacity > 0 && refillPerSecond >= 0)
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
        self.clock = clock
        self.lastRefill = clock.now()
    }

    public var available: Double {
        refill()
        return tokens
    }

    public func tryTake(_ count: Double = 1) -> Bool {
        refill()
        guard tokens >= count else { return false }
        tokens -= count
        return true
    }

    public func waitTime(for count: Double = 1) -> TimeInterval {
        refill()
        if tokens >= count { return 0 }
        guard refillPerSecond > 0 else { return .infinity }
        return (count - tokens) / refillPerSecond
    }

    private func refill() {
        let now = clock.now()
        tokens = min(capacity, tokens + (now - lastRefill) * refillPerSecond)
        lastRefill = now
    }
}
