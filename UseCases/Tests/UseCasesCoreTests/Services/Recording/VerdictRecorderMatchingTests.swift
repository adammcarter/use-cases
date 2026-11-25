import Testing
@testable import UseCasesCore

struct VerdictRecorderMatchingTests {
  private func match(
    _ target: String,
    among ids: [String],
  ) -> PrefixMatch<String> {
    VerdictRecorder.match(
      target,
      among: ids,
      by: { $0 },
    )
  }

  @Test
  func `the exact id is the match, though others start with it`() {
    guard case let .found(item) = match("a.b", among: ["a.b-two", "a.b", "a.bc"]) else {
      Issue.record("expected the exact id")
      return
    }

    #expect(item == "a.b")
  }

  @Test
  func `the one id that starts with the text is the match`() {
    guard case let .found(item) = match("a.b", among: ["a.bc", "x.y"]) else {
      Issue.record("expected the one id")
      return
    }

    #expect(item == "a.bc")
  }

  @Test
  func `several ids that start with the text are listed in byte order`() {
    guard case let .several(ids) = match("a", among: ["a.c", "a.B", "a.b"]) else {
      Issue.record("expected several")
      return
    }

    #expect(ids == ["a.B", "a.b", "a.c"])
  }

  @Test(arguments: ["z", "A", "a.bcd", " a"])
  func `text that starts no id matches nothing`(target: String) {
    guard case .none = match(target, among: ["a.b", "a.c"]) else {
      Issue.record("expected nothing")
      return
    }
  }

  @Test
  func `the empty text starts everything, so it is the match only of a lone id`() {
    guard case .found = match("", among: ["only"]) else {
      Issue.record("expected the lone id")
      return
    }
    guard case .several = match("", among: ["one", "two"]) else {
      Issue.record("expected several")
      return
    }
  }

  @Test
  func `an id in another Unicode form is not the same id`() {
    guard case .none = match("e\u{301}", among: ["\u{E9}"]) else {
      Issue.record("expected nothing")
      return
    }
  }
}
