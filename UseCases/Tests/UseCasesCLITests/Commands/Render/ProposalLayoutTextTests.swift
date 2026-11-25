import Testing
import UseCasesCore
@testable import UseCasesCLI

struct ProposalLayoutTextTests {
  private static let layout = ProposalLayout(
    title: "Lock accounts after too many wrong passwords",
    changes: [
      ProposalChange(
        useCase: "shop.login.unlock-email",
        fit: .new,
        title: "Unlock by email link",
        tier: "critical",
        youSee: "\"Locked? Check your email\"",
      ),
      ProposalChange(
        useCase: "shop.login.signin",
        fit: .changes,
        title: "Sign in",
        tier: "critical",
        youSee: "a lock message after 5 tries",
      ),
      ProposalChange(
        useCase: "shop.login.unlock-phone",
        fit: .replaces,
        title: "Unlock by phoning support",
        tier: "core",
        youSee: nil,
      ),
      ProposalChange(
        useCase: "shop.login.remember",
        fit: .untouched,
        title: "Remember me",
        tier: "core",
        youSee: nil,
      ),
    ],
    decisions: [
      ProposalDecision(
        question: "how long a lock lasts",
        options: ["15 minutes", "until unlocked by email"],
      ),
    ],
    signOff: SignOffCounts(critical: 2, core: 1, supporting: 0),
  )

  @Test
  func `the proposal is the whole change on one screen, ids last`() {
    #expect(Self.layout.text(style: .plain).components(separatedBy: "\n") == [
      "PROPOSAL · Lock accounts after too many wrong passwords",
      "",
      "  + NEW        Unlock by email link        you'll see: \"Locked? Check your email\"",
      "  ~ CHANGES    Sign in                     you'll see: a lock message after 5 tries",
      "  − REPLACES   Unlock by phoning support",
      "  = UNTOUCHED  Remember me                 (checked, stays as it is)",
      "",
      "  YOUR CALL    how long a lock lasts:  1) 15 minutes   2) until unlocked by email",
      "  SIGN-OFF     yours: 2 critical, 1 core",
      "  ids          shop.login.unlock-email · shop.login.signin · shop.login.unlock-phone"
        + " · shop.login.remember",
    ])
  }

  @Test
  func `the title of the proposal is collapsed to words`() {
    let layout = ProposalLayout(
      title: "Lock  accounts\n\tafter   too many",
      changes: [ProposalChange(useCase: "a.b.c", fit: .new, title: "X", tier: nil, youSee: nil)],
      decisions: [],
      signOff: SignOffCounts(critical: 0, core: 0, supporting: 0),
    )

    #expect(layout.text(style: .plain).hasPrefix("PROPOSAL · Lock accounts after too many\n"))
  }

  @Test
  func `a proposal with no choices and nobody to sign has neither line`() {
    let layout = ProposalLayout(
      title: "T",
      changes: [ProposalChange(useCase: "a.b.c", fit: .new, title: "X", tier: nil, youSee: nil)],
      decisions: [],
      signOff: SignOffCounts(critical: 0, core: 0, supporting: 0),
    )

    #expect(layout
      .text(style: .plain) == "PROPOSAL · T\n\n  + NEW        X\n\n  ids          a.b.c")
  }

  @Test
  func `an untouched use case with something to see shows that and not the note`() {
    let layout = ProposalLayout(
      title: "T",
      changes: [
        ProposalChange(useCase: "a.b.c", fit: .untouched, title: "X", tier: nil, youSee: "same"),
      ],
      decisions: [],
      signOff: SignOffCounts(critical: 0, core: 0, supporting: 0),
    )

    #expect(layout.text(style: .plain).contains("  = UNTOUCHED  X   you'll see: same"))
    #expect(!layout.text(style: .plain).contains("checked"))
  }

  @Test
  func `titles are padded in scalars, so a wide one does not push the column`() {
    let layout = ProposalLayout(
      title: "T",
      changes: [
        ProposalChange(useCase: "a.b.c", fit: .new, title: "Café→", tier: nil, youSee: "x"),
        ProposalChange(useCase: "a.b.d", fit: .new, title: "Cafe", tier: nil, youSee: "y"),
      ],
      decisions: [],
      signOff: SignOffCounts(critical: 0, core: 0, supporting: 0),
    )
    let rows = layout.text(style: .plain).components(separatedBy: "\n").filter { line in
      line.contains("you'll")
    }

    #expect(rows == [
      "  + NEW        Café→   you'll see: x",
      "  + NEW        Cafe    you'll see: y",
    ])
  }

  @Test
  func `supporting use cases are signed by an agent where the person said it may`() {
    #expect(
      SignOffCounts(critical: 0, core: 0, supporting: 2).words
        == "supporting: 2 (an agent's, where you said it may)",
    )
    #expect(
      SignOffCounts(critical: 1, core: 0, supporting: 2).words
        == "yours: 1 critical · supporting: 2 (an agent's, where you said it may)",
    )
    #expect(SignOffCounts(critical: 0, core: 3, supporting: 0).words == "yours: 3 core")
    #expect(SignOffCounts(critical: 0, core: 0, supporting: 0).words == nil)
  }

  @Test(arguments: [
    (ProposalFit.new, "+"),
    (.extends, "~"),
    (.changes, "~"),
    (.replaces, "−"),
    (.untouched, "="),
  ])
  func `the symbols are the fits of the design`(
    fit: ProposalFit,
    symbol: String,
  ) {
    #expect(fit.symbol == symbol)
  }

  @Test
  func `bold applies to the headers and the fit words, after they are padded`() {
    let text = Self.layout.text(style: .bold)

    #expect(text
      .hasPrefix("\u{1B}[1mPROPOSAL · Lock accounts after too many wrong passwords\u{1B}[0m\n"))
    #expect(text.contains("  = \u{1B}[1mUNTOUCHED\u{1B}[0m  Remember me"))
    #expect(text.contains("  + \u{1B}[1mNEW      \u{1B}[0m  Unlock by email link"))
    #expect(text.contains("  \u{1B}[1mYOUR CALL\u{1B}[0m    how long"))
    #expect(text.contains("  \u{1B}[1mSIGN-OFF\u{1B}[0m     yours"))
    #expect(text.contains("  \u{1B}[1mids\u{1B}[0m          shop.login.unlock-email"))
  }
}
