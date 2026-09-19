import Testing
@testable import UseCasesCore

/// Pins two things about `RegularExpression.matches`: it is still correct for
/// a schema `pattern` value and for a pattern no embedded schema declares, and
/// repeated calls with a schema pattern are actually served from the cache
/// rather than recompiled — the regression measured on a real 803-row
/// workspace, where `scan` cost roughly twenty seconds instead of one because
/// every property on every row recompiled the same six patterns from scratch.
struct RegularExpressionTests {
  @Test(arguments: [
    ("checkout-success", "^[a-z0-9_-]+$", true),
    ("checkout.success", "^[a-z0-9_-]+$", false),
    ("sha256:" + String(repeating: "a", count: 64), "^sha256:[0-9a-f]{64}$", true),
    ("sha256:short", "^sha256:[0-9a-f]{64}$", false),
  ])
  func `a schema pattern matches exactly as it did uncached`(
    text: String,
    pattern: String,
    expected: Bool,
  ) {
    #expect(RegularExpression.matches(text, pattern) == expected)
  }

  @Test
  func `a pattern no embedded schema declares still matches, via the fallback path`() {
    #expect(RegularExpression.matches("2026-09-19", #"^\d{4}-\d{2}-\d{2}$"#))
    #expect(!RegularExpression.matches("not a date", #"^\d{4}-\d{2}-\d{2}$"#))
  }

  @Test
  func `repeated calls with a schema pattern are served from the cache, not recompiled`() {
    let pattern = "^[a-z0-9_-]+$"
    let text = "checkout-success"
    // Deliberately not a schema `pattern` value or one of YamlParser's own
    // fixed patterns, so `matches` always falls to the uncached recompile
    // path — this is the "recompiled every call" side of the comparison.
    let uncachedPattern = "^this-pattern-is-never-precompiled-by-any-schema$"
    let uncachedText = "irrelevant"
    let iterations = 20000

    // One cold call each pays for any lazy first-touch cost the cache itself
    // has; excluded from the timed runs below.
    _ = RegularExpression.matches(text, pattern)
    _ = RegularExpression.matches(uncachedText, uncachedPattern)

    let cachedStarted = ContinuousClock.now
    for _ in 0 ..< iterations {
      _ = RegularExpression.matches(text, pattern)
    }
    let cachedElapsed = ContinuousClock.now - cachedStarted

    let uncachedStarted = ContinuousClock.now
    for _ in 0 ..< iterations {
      _ = RegularExpression.matches(uncachedText, uncachedPattern)
    }
    let uncachedElapsed = ContinuousClock.now - uncachedStarted

    // Measured on a quiet machine at 200,000 calls each: 3.44s recompiling
    // from scratch every call, 0.37s served from the cache — a 9x gap.
    // Comparing the two back to back, in the SAME run, rather than against
    // an absolute ceiling, is what survives a busy CI box: contention slows
    // both loops by roughly the same factor, so the ratio holds even when
    // neither absolute number does. 3x is a third of the measured gap.
    #expect(cachedElapsed * 3 < uncachedElapsed)
  }
}
