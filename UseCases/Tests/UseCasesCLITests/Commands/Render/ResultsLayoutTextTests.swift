import Testing
import UseCasesCore
@testable import UseCasesCLI

struct ResultsLayoutTextTests {
  private static let layout = ResultsLayout(
    title: "Lock accounts after too many wrong passwords",
    useCases: [
      ResultUseCase(
        useCase: "shop.login.signin",
        title: "Sign in",
        status: .verified,
        checks: [
          ResultCheck(label: "unit-tests", status: .verified),
          ResultCheck(label: "staging", status: .verified),
        ],
      ),
      ResultUseCase(
        useCase: "shop.login.unlock-email",
        title: "Unlock by email link",
        status: .failed,
        checks: [
          ResultCheck(label: "unit-tests", status: .failed),
          ResultCheck(label: "staging", status: .unverified),
        ],
      ),
      ResultUseCase(
        useCase: "shop.login.draft",
        title: "Not ready",
        status: .draft,
        checks: [],
      ),
    ],
    removed: ["shop.login.unlock-phone"],
    gatePasses: true,
  )

  @Test
  func `what was done, how each change was proven, the removed ones by id, the gate and the ids`() {
    #expect(Self.layout.text(style: .plain).components(separatedBy: "\n") == [
      "RESULTS · Lock accounts after too many wrong passwords",
      "",
      "  ✓ Sign in                   unit-tests ✓ · staging ✓",
      "  ✗ Unlock by email link      unit-tests ✗ · staging ○",
      "  · Not ready",
      "  − shop.login.unlock-phone   removed",
      "  gate   passes",
      "  ids    shop.login.signin · shop.login.unlock-email · shop.login.draft"
        + " · shop.login.unlock-phone",
    ])
  }

  @Test
  func `a gate that blocks says so`() {
    let layout = ResultsLayout(title: "T", useCases: [], removed: ["a.b.c"], gatePasses: false)

    #expect(
      layout.text(style: .plain)
        == "RESULTS · T\n\n  − a.b.c        removed\n  gate   blocked\n  ids    a.b.c",
    )
  }

  @Test
  func `bold applies to the headers alone`() {
    let layout = ResultsLayout(title: "T", useCases: [], removed: [], gatePasses: true)

    let bold = layout.text(style: .bold)

    #expect(bold.hasPrefix("\u{1B}[1mRESULTS · T\u{1B}[0m\n\n"))
    #expect(bold.contains("  \u{1B}[1mgate\u{1B}[0m   passes\n"))
    #expect(bold.hasSuffix("  \u{1B}[1mids\u{1B}[0m    "))
  }
}
