import Testing
@testable import UseCasesCore

struct SearchReasonTests {
  private func text(_ text: String) -> String {
    SearchReason(
      field: .title,
      location: nil,
      text: text,
    ).text
  }

  @Test
  func `text of 160 characters or fewer is kept whole`() {
    let exact = String(repeating: "a", count: 160)

    #expect(text(exact) == exact)
    #expect(text("") == "")
    #expect(text("short") == "short")
  }

  @Test
  func `longer text is cut to 160 characters`() {
    let cut = text(String(repeating: "a", count: 161))

    #expect(cut.count == 160)
  }

  @Test
  func `a character made of several scalars is never cut in half`() {
    let family = "👨‍👩‍👧"
    let cut = text(String(repeating: family, count: 100))

    #expect(cut.count <= 160)
    #expect(cut.unicodeScalars.count <= 160)
    #expect(cut.count == cut.unicodeScalars.count / 5)
    #expect(cut == String(repeating: family, count: cut.count))
  }

  @Test
  func `an accent on the last letter is kept with it`() {
    let accented = String(repeating: "e\u{301}", count: 100)
    let cut = text(accented)

    #expect(cut.count == 80)
    #expect(cut.unicodeScalars.count == 160)
  }
}
