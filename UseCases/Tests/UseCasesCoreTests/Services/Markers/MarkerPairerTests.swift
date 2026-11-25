import Testing
@testable import UseCasesCore

struct MarkerPairerTests {
  private let pairer = MarkerPairer()

  /// A sentinel at a made-up place; only its kind, id and line matter to pairing.
  private func sentinel(
    _ kind: MarkerSentinelKind,
    _ identifier: String,
    line: Int,
  ) -> MarkerSentinel {
    MarkerSentinel(
      kind: kind,
      identifier: identifier,
      tokenRange: (line * 100) ..< (line * 100 + 10),
      line: line,
    )
  }

  @Test
  func `a start and the end after it pair`() {
    let start = sentinel(.start, "a#b", line: 1)
    let end = sentinel(.end, "a#b", line: 2)

    let outcome = pairer.pair([start, end])

    #expect(outcome.pairs == [MarkerPair(start: start, end: end)])
    #expect(outcome.problems.isEmpty)
  }

  @Test
  func `different markers nest`() {
    let outerStart = sentinel(.start, "a#a", line: 1)
    let innerStart = sentinel(.start, "b#b", line: 2)
    let innerEnd = sentinel(.end, "b#b", line: 3)
    let outerEnd = sentinel(.end, "a#a", line: 4)

    let outcome = pairer.pair([outerStart, innerStart, innerEnd, outerEnd])

    #expect(
      outcome.pairs == [
        MarkerPair(start: innerStart, end: innerEnd),
        MarkerPair(start: outerStart, end: outerEnd),
      ],
    )
    #expect(outcome.problems.isEmpty)
  }

  @Test
  func `one marker may close and open again, as many regions as it likes`() {
    let sentinels = [
      sentinel(.start, "a#b", line: 1), sentinel(.end, "a#b", line: 2),
      sentinel(.start, "a#b", line: 3), sentinel(.end, "a#b", line: 4),
      sentinel(.start, "a#b", line: 5), sentinel(.end, "a#b", line: 6),
    ]

    let outcome = pairer.pair(sentinels)

    #expect(outcome.pairs.count == 3)
    #expect(outcome.problems.isEmpty)
  }

  @Test
  func `an end with no start is a problem`() {
    let end = sentinel(.end, "a#b", line: 1)

    #expect(pairer.pair([end]).problems == [.withoutStart(end)])
  }

  @Test
  func `an end after its pair is closed has no start`() {
    let sentinels = [
      sentinel(.start, "a#b", line: 1),
      sentinel(.end, "a#b", line: 2),
      sentinel(.end, "a#b", line: 3),
    ]

    #expect(pairer.pair(sentinels).problems == [.withoutStart(sentinels[2])])
  }

  @Test
  func `a start never closed is a problem`() {
    let start = sentinel(.start, "a#b", line: 1)

    #expect(pairer.pair([start]).problems == [.neverClosed(start)])
  }

  @Test
  func `an end for another marker leaves the start open and itself without a start`() {
    let start = sentinel(.start, "a#a", line: 1)
    let end = sentinel(.end, "b#b", line: 2)

    let outcome = pairer.pair([start, end])

    #expect(outcome.pairs.isEmpty)
    #expect(outcome.problems == [.withoutStart(end), .neverClosed(start)])
  }

  @Test
  func `crossing pairs are one problem at the end that crosses`() {
    let startA = sentinel(.start, "a#a", line: 1)
    let startB = sentinel(.start, "b#b", line: 2)
    let endA = sentinel(.end, "a#a", line: 3)
    let endB = sentinel(.end, "b#b", line: 4)

    let outcome = pairer.pair([startA, startB, endA, endB])

    #expect(outcome.problems == [.crossing(end: endA, start: startA, stillOpen: startB)])
  }

  @Test
  func `a crossing names the first start still open after the one being closed`() {
    let startA = sentinel(.start, "a#a", line: 1)
    let startD = sentinel(.start, "d#d", line: 2)
    let startG = sentinel(.start, "g#g", line: 3)
    let endA = sentinel(.end, "a#a", line: 4)

    let problems = pairer.pair([startA, startD, startG, endA]).problems

    #expect(problems.first == .crossing(end: endA, start: startA, stillOpen: startD))
  }

  @Test
  func `the same marker nested inside itself is a problem at the inner start`() {
    let outer = sentinel(.start, "a#b", line: 1)
    let inner = sentinel(.start, "a#b", line: 2)
    let sentinels = [
      outer, inner, sentinel(.end, "a#b", line: 3), sentinel(.end, "a#b", line: 4),
    ]

    #expect(pairer.pair(sentinels).problems == [.nestedInItself(inner, outer: outer)])
  }

  @Test
  func `three starts of one marker nest twice over`() {
    let sentinels = [
      sentinel(.start, "a#b", line: 1), sentinel(.start, "a#b", line: 2),
      sentinel(.start, "a#b", line: 3), sentinel(.end, "a#b", line: 4),
      sentinel(.end, "a#b", line: 5), sentinel(.end, "a#b", line: 6),
    ]

    let problems = pairer.pair(sentinels).problems

    #expect(
      problems == [
        .nestedInItself(sentinels[1], outer: sentinels[0]),
        .nestedInItself(sentinels[2], outer: sentinels[1]),
      ],
    )
  }

  @Test
  func `no sentinels give nothing`() {
    let outcome = pairer.pair([])

    #expect(outcome.pairs.isEmpty)
    #expect(outcome.problems.isEmpty)
  }

  @Test
  func `a deep stack of different markers pairs`() {
    let depth = 2000
    var sentinels: [MarkerSentinel] = []

    for level in 1 ... depth {
      sentinels.append(sentinel(.start, "a#m\(level)", line: level))
    }

    for level in (1 ... depth).reversed() {
      sentinels.append(sentinel(.end, "a#m\(level)", line: depth + level))
    }

    let outcome = pairer.pair(sentinels)

    #expect(outcome.pairs.count == depth)
    #expect(outcome.problems.isEmpty)
  }
}
