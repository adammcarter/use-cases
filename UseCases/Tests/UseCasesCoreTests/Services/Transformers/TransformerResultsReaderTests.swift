import Testing
@testable import UseCasesCore

struct TransformerResultsReaderTests {
  private static let first = "demo.a#unit-tests.t@tests/a.py:3"
  private static let second = "demo.b#unit-tests.u@tests/b.py:1"

  private func read(
    _ text: String,
    links: Set<String> = [first, second],
  ) throws -> TransformerResults {
    try TransformerResultsReader().read(
      AuthoredObject(
        JSONReader().read(text),
        at: "",
      ),
      from: "tools/results",
      links: links,
    )
  }

  /// One entry of `results`; `rest` is more members, written as `,"name":value`.
  private func entry(
    _ link: String,
    _ status: String,
    rest: String = "",
  ) -> String {
    "{\"link\":\"" + link + "\",\"status\":\"" + status + "\"" + rest + "}"
  }

  /// A whole response whose `results` are these entries.
  private func wrap(_ entries: String...) -> String {
    "{\"contract\":1,\"results\":[" + entries.joined(separator: ",")
      + "],\"unlinked\":[],\"diagnostics\":[]}"
  }

  // MARK: - What is read

  @Test
  func `a result is a link, a status, the tests and a note`() throws {
    let found = try read(
      wrap(entry(Self.first, "pass", rest: ",\"tests\":[\"A/a\",\"A/b\"],\"message\":\"fine\"")),
    )

    #expect(
      found.results == [
        TransformerLinkResult(
          link: Self.first,
          status: .pass,
          tests: ["A/a", "A/b"],
          message: "fine",
        ),
      ],
    )
  }

  @Test(arguments: ["pass", "fail", "error", "incomplete"])
  func `each of the four statuses is read`(status: String) throws {
    let found = try read(wrap(entry(Self.first, status)))

    #expect(found.results.first?.status.rawValue == status)
    #expect(found.results.first?.tests == [])
    #expect(found.results.first?.message == nil)
  }

  @Test
  func `tests in no link and words for people are read`() throws {
    let found = try read(
      """
      {"contract":1,"results":[],"diagnostics":["one"],"unlinked":[
        {"test":"A/free","file":"tests/a.py","line":35,"status":"pass"},
        {"test":"A/lost","file":null,"line":null,"status":"fail"}]}
      """,
    )

    #expect(
      found.unlinked == [
        UnlinkedTest(test: "A/free", file: "tests/a.py", line: 35, status: .pass),
        UnlinkedTest(test: "A/lost", file: nil, line: nil, status: .fail),
      ],
    )
    #expect(found.diagnostics == ["one"])
  }

  @Test
  func `members it does not know are ignored`() throws {
    let found = try read(
      "{\"contract\":1,\"later\":true,\"results\":["
        + entry(Self.first, "pass", rest: ",\"retries\":2")
        + "],\"unlinked\":[],\"diagnostics\":[]}",
    )

    #expect(found.results.count == 1)
  }

  // MARK: - Several results for one link

  @Test(
    arguments: [
      (["pass", "pass"], Verdict.pass),
      (["pass", "incomplete"], .incomplete),
      (["incomplete", "pass"], .incomplete),
      (["pass", "error", "incomplete"], .error),
      (["error", "fail", "pass"], .fail),
      (["fail", "error"], .fail),
      (["incomplete", "error"], .error),
      (["pass", "pass", "pass", "fail"], .fail),
    ],
  )
  func `the worst result of a link wins: fail, error, incomplete, then pass`(
    statuses: [String],
    worst: Verdict,
  ) throws {
    let entries = statuses.map { status in
      entry(Self.first, status)
    }

    let found = try read("{\"contract\":1,\"results\":[" + entries.joined(separator: ",")
      + "],\"unlinked\":[],\"diagnostics\":[]}")

    #expect(found.results.count == 1)
    #expect(found.results.first?.status == worst)
  }

  @Test
  func `merged results keep the tests of both without repeats, and the winner's note`() throws {
    let found = try read(
      wrap(
        entry(Self.first, "pass", rest: ",\"tests\":[\"a\",\"b\"],\"message\":\"first\""),
        entry(Self.first, "fail", rest: ",\"tests\":[\"b\",\"c\"],\"message\":\"second\""),
      ),
    )

    #expect(found.results.first?.tests == ["a", "b", "c"])
    #expect(found.results.first?.message == "second")
  }

  @Test
  func `a tie keeps the first note, and a winner with no note takes the other's`() throws {
    let tie = try read(
      wrap(
        entry(Self.first, "fail", rest: ",\"message\":\"first\""),
        entry(Self.first, "fail", rest: ",\"message\":\"second\""),
      ),
    )
    let silent = try read(
      wrap(
        entry(Self.first, "pass", rest: ",\"message\":\"kept\""),
        entry(Self.first, "fail"),
      ),
    )

    #expect(tie.results.first?.message == "first")
    #expect(silent.results.first?.message == "kept")
  }

  @Test
  func `results stay in the order links were first spoken of`() throws {
    let found = try read(
      wrap(
        entry(Self.second, "pass"),
        entry(Self.first, "pass"),
        entry(Self.second, "fail"),
      ),
    )

    #expect(found.results.map(\.link) == [Self.second, Self.first])
    #expect(found.results.first?.status == .fail)
  }

  // MARK: - What is refused

  @Test(
    arguments: [
      "{\"contract\":1,\"results\":[{\"link\":\"made-up\",\"status\":\"fail\"}]}",
      "{\"contract\":1,\"results\":[{\"link\":\"made-up\",\"status\":\"fail\"}],"
        + "\"unlinked\":[],\"diagnostics\":[]}",
      "{\"contract\":1,\"results\":[{\"link\":\"made-up\",\"status\":\"fail\"}],\"unlinked\":7}",
      "{\"contract\":1,\"results\":[{\"link\":\"made-up\",\"status\":\"nonsense\"}]}",
    ],
  )
  func `a result naming a link that is not in the request is told first, whatever else is wrong`(
    text: String,
  ) {
    #expect(
      throws: TransformerError.unknownResultLink(name: "tools/results", link: "made-up"),
    ) {
      try read(text)
    }
  }

  @Test(arguments: ["Pass", "FAIL", "skipped", "xfail", "", "ok", "passed"])
  func `a status other than the four is refused, and names the link`(status: String) {
    #expect(
      throws: TransformerError.invalidResultStatus(
        name: "tools/results",
        link: Self.first,
        status: status,
      ),
    ) {
      try read(wrap(entry(Self.first, status)))
    }
  }

  @Test
  func `a link that is in no request is refused even when it is a real key of another run`() {
    let error = TransformerError.unknownResultLink(name: "tools/results", link: Self.second)

    #expect(throws: error) {
      try read(
        wrap(entry(Self.second, "pass")),
        links: [Self.first],
      )
    }
  }

  @Test(
    arguments: [
      ("{\"contract\":1,\"unlinked\":[],\"diagnostics\":[]}", "results: this is required"),
      ("{\"contract\":1,\"results\":[],\"diagnostics\":[]}", "unlinked: this is required"),
      ("{\"contract\":1,\"results\":[],\"unlinked\":[]}", "diagnostics: this is required"),
      ("{\"contract\":1}", "results: this is required"),
    ],
  )
  func `after the results are checked, a member that is missing is malformed`(
    text: String,
    reason: String,
  ) {
    #expect(throws: TransformerError.malformedResponse(name: "tools/results", reason: reason)) {
      try read(text)
    }
  }

  @Test(
    arguments: [
      (
        "{\"contract\":1,\"results\":{},\"unlinked\":[],\"diagnostics\":[]}",
        "results: this must be a list",
      ),
      (
        "{\"contract\":1,\"results\":[3],\"unlinked\":[],\"diagnostics\":[]}",
        "results[0]: this must be a mapping",
      ),
      (
        "{\"contract\":1,\"results\":[{\"status\":\"pass\"}],\"unlinked\":[],\"diagnostics\":[]}",
        "results[0].link: this is required",
      ),
      (
        "{\"contract\":1,\"results\":[{\"link\":5,\"status\":\"pass\"}],\"unlinked\":[],"
          + "\"diagnostics\":[]}",
        "results[0].link: this must be text",
      ),
      (
        "{\"contract\":1,\"results\":[{\"link\":\"a\"}],\"unlinked\":[],\"diagnostics\":[]}",
        "results[0].status: this is required",
      ),
      (
        "{\"contract\":1,\"results\":[{\"link\":\"a\",\"status\":true}],\"unlinked\":[],"
          + "\"diagnostics\":[]}",
        "results[0].status: this must be text",
      ),
      (
        "{\"contract\":1,\"results\":[],\"unlinked\":{},\"diagnostics\":[]}",
        "unlinked: this must be a list",
      ),
      (
        "{\"contract\":1,\"results\":[],\"unlinked\":[{\"test\":1}],\"diagnostics\":[]}",
        "unlinked[0].test: this must be text",
      ),
      (
        "{\"contract\":1,\"results\":[],\"unlinked\":[],\"diagnostics\":[1]}",
        "diagnostics[0]: this must be text",
      ),
    ],
  )
  func `a known member of the wrong type is malformed, and says where`(
    text: String,
    reason: String,
  ) {
    #expect(throws: TransformerError.malformedResponse(name: "tools/results", reason: reason)) {
      try read(text)
    }
  }

  @Test(arguments: [",\"tests\":\"a\"", ",\"message\":4"])
  func `tests of the wrong type, or a note that is not text, are malformed`(rest: String) {
    #expect(throws: TransformerError.self) {
      try read(wrap(entry(Self.first, "pass", rest: rest)))
    }
  }
}
