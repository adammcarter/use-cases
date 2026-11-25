import Testing
@testable import UseCasesTransformers

struct LinkAttributorPlacementTests {
  @Test
  func `a test with no line is outside a link that has a range`() {
    let link = RequestLink.validation(
      "tests/a.py",
      1,
      9,
    )

    let response = LinkAttributor.response(
      links: [link],
      located: [located(
        "t",
        "tests/a.py",
        nil,
        .pass,
      )],
      diagnostics: [],
    )

    #expect(response.status(of: link) == nil)
    #expect(response.unlinked.count == 1)
  }

  @Test
  func `a test that could not be placed is unlinked, with null file and line`() {
    let link = RequestLink.validation(
      "tests/a.py",
      1,
      9,
    )

    let response = LinkAttributor.response(
      links: [link],
      located: [located(
        "t",
        nil,
        nil,
        .pass,
      )],
      diagnostics: [],
    )

    #expect(response.results.isEmpty)
    #expect(response.unlinked == [UnlinkedTest(
      test: "t",
      file: nil,
      line: nil,
      status: .pass,
    )])
  }

  @Test
  func `implementation links never receive results`() {
    let implementation = RequestLink.implementation(
      "tests/a.py",
      1,
      9,
    )

    let response = LinkAttributor.response(
      links: [implementation],
      located: [located(
        "t",
        "tests/a.py",
        3,
        .pass,
      )],
      diagnostics: [],
    )

    #expect(response.results.isEmpty)
    #expect(response.unlinked.count == 1)
  }

  @Test
  func `a test inside two links counts for both`() {
    let first = RequestLink.validation(
      "tests/a.py",
      1,
      9,
      binding: "one",
    )
    let second = RequestLink.validation(
      "tests/a.py",
      3,
      5,
      binding: "two",
    )

    let response = LinkAttributor.response(
      links: [first, second],
      located: [located(
        "t",
        "tests/a.py",
        4,
        .fail,
      )],
      diagnostics: [],
    )

    #expect(response.status(of: first) == .fail)
    #expect(response.status(of: second) == .fail)
  }

  @Test
  func `results are in key order`() {
    let later = RequestLink.validation(
      "tests/b.py",
      1,
      9,
      binding: "b",
    )
    let earlier = RequestLink.validation(
      "tests/a.py",
      1,
      9,
      binding: "a",
    )

    let response = LinkAttributor.response(
      links: [later, earlier],
      located: [
        located(
          "t",
          "tests/b.py",
          2,
          .pass,
        ),
        located(
          "t",
          "tests/a.py",
          2,
          .pass,
        ),
      ],
      diagnostics: ["kept"],
    )

    #expect(response.results.map(\.link) == [earlier.key, later.key])
    #expect(response.diagnostics == ["kept"])
  }

  @Test
  func `unlinked tests are in file, line, test order`() {
    let response = LinkAttributor.response(
      links: [],
      located: [
        located(
          "z",
          "tests/c.py",
          9,
          .pass,
        ),
        located(
          "y",
          "tests/c.py",
          9,
          .pass,
        ),
        located(
          "x",
          "tests/c.py",
          1,
          .pass,
        ),
        located(
          "n",
          nil,
          nil,
          .pass,
        ),
      ],
      diagnostics: [],
    )

    #expect(response.unlinked.map(\.test) == ["n", "x", "y", "z"])
  }

  @Test(arguments: [0, -1, Int.min])
  func `a line below 1 is never written out`(line: Int) {
    let response = LinkAttributor.response(
      links: [],
      located: [located(
        "t",
        "tests/a.py",
        line,
        .pass,
      )],
      diagnostics: [],
    )

    #expect(response.unlinked == [UnlinkedTest(
      test: "t",
      file: "tests/a.py",
      line: nil,
      status: .pass,
    )])
  }
}
