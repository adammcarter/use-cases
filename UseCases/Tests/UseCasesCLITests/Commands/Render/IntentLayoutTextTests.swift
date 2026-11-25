import Testing
import UseCasesCore
@testable import UseCasesCLI

struct IntentLayoutTextTests {
  @Test
  func `what, why and who, who's names joined with a dot`() {
    let layout = IntentLayout(
      what: "Refund part of an invoice",
      why: "Customers return single items",
      who: ["support staff", "customers"],
    )

    #expect(layout.text(style: .plain).split(separator: "\n") == [
      "WHAT   Refund part of an invoice",
      "WHY    Customers return single items",
      "WHO    support staff · customers",
    ])
  }

  @Test
  func `who is left out when nobody is named`() {
    let layout = IntentLayout(what: "x", why: "y", who: [])

    #expect(layout.text(style: .plain) == "WHAT   x\nWHY    y")
  }

  @Test
  func `a line break inside a field never breaks the layout`() {
    let layout = IntentLayout(what: "one\ntwo", why: "a\n\nb", who: ["c\nd"])

    #expect(layout.text(style: .plain) == "WHAT   one two\nWHY    a b\nWHO    c d")
  }

  @Test
  func `bold applies to the headers alone`() {
    let layout = IntentLayout(what: "x", why: "y", who: ["z"])

    #expect(
      layout.text(style: .bold)
        == "\u{1B}[1mWHAT\u{1B}[0m   x\n\u{1B}[1mWHY\u{1B}[0m    y\n\u{1B}[1mWHO\u{1B}[0m    z",
    )
  }
}
