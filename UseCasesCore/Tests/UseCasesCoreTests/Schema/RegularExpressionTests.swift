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

    // One cold call pays for any lazy first-touch cost the cache itself has;
    // it is excluded from the timed run below.
    _ = RegularExpression.matches(text, pattern)

    let started = ContinuousClock.now
    for _ in 0 ..< 200_000 {
      #expect(RegularExpression.matches(text, pattern))
    }
    let elapsed = ContinuousClock.now - started

    // Measured on this machine, 200,000 calls: 3.44s recompiling the pattern
    // from scratch on every call, 0.37s served from the cache — a clean 9x
    // gap. One second sits comfortably between the two, so it fails if the
    // cache goes missing while leaving wide room for slower CI hardware.
    #expect(elapsed < .seconds(1))
  }
}
