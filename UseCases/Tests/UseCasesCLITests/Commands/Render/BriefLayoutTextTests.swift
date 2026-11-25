import Testing
import UseCasesCore
@testable import UseCasesCLI

struct BriefLayoutTextTests {
  private static let changed = BriefCard(
    useCase: "shop.login.signin",
    fit: .changes,
    title: "Sign in",
    tier: "critical",
    now: "After 5 wrong passwords, the account locks.",
    was: "No limit.",
    scenarios: [
      BriefScenario(isGolden: true, text: "right password → signed in"),
      BriefScenario(isGolden: false, text: "5th try is right → signed in, no lock"),
    ],
    notIncluded: ["locking by IP address"],
    provenBy: ["unit tests", "you trying it on staging"],
  )

  private static func card(
    useCase: String = "a.b.c",
    title: String = "T",
    now: String = "N",
    scenarios: [BriefScenario] = [],
    notIncluded: [String] = [],
  ) -> BriefCard {
    BriefCard(
      useCase: useCase,
      fit: .new,
      title: title,
      tier: nil,
      now: now,
      was: nil,
      scenarios: scenarios,
      notIncluded: notIncluded,
      provenBy: [],
    )
  }

  private func lines(
    of card: BriefCard,
    style: LayoutStyle = .plain,
  ) -> [String] {
    card.lines(style: style)
  }

  @Test
  func `a card is the design's card, its id at the top right`() {
    #expect(lines(of: Self.changed) == [
      "┌──────────────────────────────────────── shop.login.signin ──┐",
      "│                                                             │",
      "│  CHANGES · critical                                         │",
      "│  Sign in                                                    │",
      "│                                                             │",
      "│  NOW                                                        │",
      "│    After 5 wrong passwords, the account locks.              │",
      "│                                                             │",
      "│  WAS                                                        │",
      "│    No limit.                                                │",
      "│                                                             │",
      "│  SCENARIOS                                                  │",
      "│    ✓ golden   right password → signed in                    │",
      "│    ◇ edge     5th try is right → signed in, no lock         │",
      "│                                                             │",
      "│  NOT INCLUDED                                               │",
      "│    ✗ locking by IP address                                  │",
      "│                                                             │",
      "│  PROVEN BY                                                  │",
      "│    unit tests · you trying it on staging                    │",
      "│                                                             │",
      "└─────────────────────────────────────────────────────────────┘",
    ])
  }

  @Test
  func `a card with nothing to say of a section leaves the section out`() {
    let found = lines(of: Self.card())

    let text = found.joined(separator: "\n")

    #expect(text.contains("NOW"))

    for section in ["WAS", "SCENARIOS", "NOT INCLUDED", "PROVEN BY"] {
      #expect(!text.contains(section))
    }
  }

  @Test(arguments: [
    "a.b.c",
    "shop.login.signin",
    "shop.accounts.unlock-by-email-link-for-customers-who-lost-their-password",
    "shop.accounts.this-id-is-exactly-fifty-one-characters-long-ok",
    "é.é.é",
  ])
  func `every row is as wide as the card, which grows to the id plus twelve for a long one`(
    useCase: String,
  ) {
    let found = lines(
      of: Self.card(
        useCase: useCase,
        title: "A title that is long enough to need wrapping onto a second line of the card",
        now: String(repeating: "word ", count: 30),
        scenarios: [BriefScenario(isGolden: true, text: String(repeating: "→", count: 90))],
        notIncluded: [String(repeating: "x", count: 150)],
      ),
    )
    let width = max(63, useCase.unicodeScalars.count + 12)

    #expect(found.allSatisfy { $0.unicodeScalars.count == width })
    #expect(found.first?.hasSuffix(" \(useCase) ──┐") == true)
    #expect(found.first?.hasPrefix("┌─") == true)
    #expect(found.last?.hasPrefix("└") == true)
  }

  @Test
  func `a card is exactly 63 scalars wide for an id of up to 51`() {
    let id = String(repeating: "a", count: 51)

    #expect(lines(of: Self.card(useCase: id)).first?.unicodeScalars.count == 63)
    #expect(lines(of: Self.card(useCase: id + "a")).first?.unicodeScalars.count == 64)
  }

  @Test
  func `text wraps at spaces and sits under its own words`() {
    let found = lines(
      of: Self.card(
        now: "one two three four five six seven eight nine ten eleven twelve thirteen fourteen",
        scenarios: [
          BriefScenario(
            isGolden: true,
            text: "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi",
          ),
        ],
      ),
    )

    #expect(found.contains("│    one two three four five six seven eight nine ten eleven  │"))
    #expect(found.contains("│    twelve thirteen fourteen                                 │"))
    #expect(found.contains("│    ✓ golden   alpha beta gamma delta epsilon zeta eta       │"))
    #expect(found.contains("│               theta iota kappa lambda mu nu xi              │"))
  }

  @Test
  func `a word too long for a line is broken where the line ends`() {
    let found = lines(of: Self.card(now: String(repeating: "x", count: 100)))

    #expect(found.contains("│    " + String(repeating: "x", count: 55) + "  │"))
    #expect(found.contains("│    " + String(repeating: "x", count: 45) + String(
      repeating: " ",
      count: 12,
    ) + "│"))
  }

  @Test
  func `a line break or a tab inside a field never reaches a row of its own`() {
    let found = lines(of: Self.card(title: "Two\nlines", now: "one\n\ntwo\tthree"))

    let text = found.joined()

    #expect(!text.contains("\n") && !text.contains("\t"))
    #expect(found.contains("│  Two lines                                                  │"))
    #expect(found.contains("│    one two three                                            │"))
  }

  @Test
  func `bold is applied to the headers after the rows are laid out, so the rows stay as wide`() {
    let plain = lines(of: Self.changed)
    let bold = lines(of: Self.changed, style: .bold)
    let stripped = bold.map { line in
      line.replacingOccurrences(of: "\u{1B}[1m", with: "").replacingOccurrences(
        of: "\u{1B}[0m",
        with: "",
      )
    }

    #expect(stripped == plain)
    #expect(bold
      .contains(
        "│  \u{1B}[1mCHANGES · critical\u{1B}[0m                                         │",
      ))
    #expect(bold.contains("│  Sign in                                                    │"))
  }

  @Test
  func `cards are drawn one after the other with a blank line between`() {
    let layout = BriefLayout(cards: [Self.card(useCase: "a.b.c"), Self.card(useCase: "a.b.d")])
    let found = layout.text(style: .plain).components(separatedBy: "\n")

    #expect(found.filter(\.isEmpty).count == 1)
    let tops = found.filter { line in
      line.hasPrefix("┌")
    }

    #expect(tops.count == 2)
  }
}
