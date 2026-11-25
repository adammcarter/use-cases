import Testing
@testable import UseCasesTransformers

struct LinkAttributorTests {
  @Test
  func `a test goes to the validation link whose lines contain it`() {
    let inside = RequestLink.validation(
      "tests/a.py",
      3,
      6,
    )
    let outside = RequestLink.validation(
      "tests/a.py",
      10,
      12,
      binding: "other",
    )

    let response = LinkAttributor.response(
      links: [inside, outside],
      located: [located(
        "t",
        "tests/a.py",
        4,
        .pass,
      )],
      diagnostics: [],
    )

    #expect(response.status(of: inside) == .pass)
    #expect(response.status(of: outside) == nil)
    #expect(response.unlinked.isEmpty)
  }

  @Test(arguments: [(2, false), (3, true), (6, true), (7, false)])
  func `the first and last line of a link are inside it`(
    line: Int,
    isInside: Bool,
  ) {
    let link = RequestLink.validation(
      "tests/a.py",
      3,
      6,
    )

    let response = LinkAttributor.response(
      links: [link],
      located: [located(
        "t",
        "tests/a.py",
        line,
        .pass,
      )],
      diagnostics: [],
    )

    #expect((response.status(of: link) != nil) == isInside)
    #expect(response.unlinked.isEmpty == isInside)
  }

  @Test
  func `several tests in one link give the worst, with every test named once`() throws {
    let link = RequestLink.validation(
      "tests/a.py",
      1,
      20,
    )

    let response = LinkAttributor.response(
      links: [link],
      located: [
        located(
          "b",
          "tests/a.py",
          5,
          .pass,
        ),
        located(
          "a",
          "tests/a.py",
          6,
          .incomplete,
        ),
        located(
          "c",
          "tests/a.py",
          7,
          .error,
        ),
        located(
          "c",
          "tests/a.py",
          8,
          .error,
        ),
      ],
      diagnostics: [],
    )

    let result = try #require(response.results.first)

    #expect(result.status == .error)
    #expect(result.tests == ["a", "b", "c"])
  }

  @Test
  func `fail beats error beats incomplete beats pass`() {
    let link = RequestLink.validation(
      "tests/a.py",
      1,
      20,
    )

    let response = LinkAttributor.response(
      links: [link],
      located: [
        located(
          "p",
          "tests/a.py",
          2,
          .pass,
        ),
        located(
          "e",
          "tests/a.py",
          3,
          .error,
        ),
        located(
          "f",
          "tests/a.py",
          4,
          .fail,
        ),
        located(
          "i",
          "tests/a.py",
          5,
          .incomplete,
        ),
      ],
      diagnostics: [],
    )

    #expect(response.status(of: link) == .fail)
  }

  @Test
  func `a link with no range takes every test of its file, placed or not within a line`() {
    let link = RequestLink.wholeFile("tests/a.py")

    let response = LinkAttributor.response(
      links: [link],
      located: [
        located(
          "t",
          "tests/a.py",
          nil,
          .fail,
        ),
        located(
          "u",
          "tests/other.py",
          3,
          .pass,
        ),
      ],
      diagnostics: [],
    )

    #expect(response.status(of: link) == .fail)
    #expect(response.unlinked.map(\.test) == ["u"])
  }
}
