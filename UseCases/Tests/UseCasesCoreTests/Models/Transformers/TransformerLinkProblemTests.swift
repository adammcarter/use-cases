import Testing
@testable import UseCasesCore

struct TransformerLinkProblemTests {
  private func path(_ text: String) throws -> WorkspacePath {
    try WorkspacePath(validating: text)
  }

  @Test(
    arguments: [
      (TransformerLinkProblem.unknownUseCase("app.nope"), "unknown use case 'app.nope'"),
      (TransformerLinkProblem.validationNeedsRoute, "a validation link needs a route"),
      (
        TransformerLinkProblem.unknownRoute(route: "nope", useCase: "app.toggle"),
        "unknown route 'nope': use case 'app.toggle' has no such route",
      ),
      (
        TransformerLinkProblem.implementationHasRoute("unit"),
        "an implementation link has no route, but this one names 'unit'",
      ),
      (TransformerLinkProblem.missingMember("file"), "the link has no 'file'"),
      (
        TransformerLinkProblem.unknownRole("both"),
        "the role 'both' is neither implementation nor validation",
      ),
      (
        TransformerLinkProblem.invalidBinding("Bad"),
        "the binding 'Bad' is not a valid id",
      ),
      (
        TransformerLinkProblem.rangeNotLines,
        "the range needs a start and an end, each a line counted from 1",
      ),
    ],
  )
  func `a problem with a link is told in the words the suite pins`(
    problem: TransformerLinkProblem,
    words: String,
  ) {
    #expect(problem.description == words)
  }

  @Test
  func `a file outside the project says so`() {
    let problem = TransformerLinkProblem.fileOutsideProject(.parentSegment("../outside.js"))

    #expect(problem.description.hasPrefix("the file must be a path inside the project: "))
  }

  @Test
  func `an excluded file says which exclusion leaves it out`() {
    let problem = TransformerLinkProblem.fileExcluded(
      ExclusionMatch(pattern: ".git/**", isBuiltIn: true),
    )

    #expect(problem.description.contains("an excluded folder"))
    #expect(problem.description.contains(".git/**"))
  }

  @Test
  func `a range outside the file says how many lines the file has`() throws {
    let target = try path("src/math.js")

    #expect(
      TransformerLinkProblem.range(.lineOutsideFile(line: 99, lineCount: 3), path: target)
        .description
        == "the range is outside the file: it reaches line 99, but 'src/math.js' has 3 lines",
    )
    #expect(
      TransformerLinkProblem.range(.lineOutsideFile(line: 2, lineCount: 1), path: target)
        .description
        == "the range is outside the file: it reaches line 2, but 'src/math.js' has 1 line",
    )
    #expect(
      TransformerLinkProblem.range(.lineOutsideFile(line: 1, lineCount: 0), path: target)
        .description
        == "the range is outside the file: it reaches line 1, but 'src/math.js' has no lines",
    )
  }

  @Test
  func `a range that starts after it ends, or cannot be cut from binary, says so`() throws {
    let target = try path("a.bin")

    #expect(
      TransformerLinkProblem.range(.startsAfterEnd, path: target).description
        == "the range starts after it ends in 'a.bin'",
    )
    #expect(
      TransformerLinkProblem.range(.notText, path: target).description
        == "a range can only be cut from text, and 'a.bin' is not strict UTF-8",
    )
  }

  @Test
  func `a file that is missing, spelled differently or behind a symlink says which`() throws {
    let target = try path("src/Math.js")

    let missing = TransformerLinkProblem.file(.path(.missing), path: target)
    let spelled = TransformerLinkProblem.file(
      .path(.spelledDifferently(written: "Math.js", onDisk: "math.js")),
      path: target,
    )
    let behind = try TransformerLinkProblem.file(
      .path(.behindSymlink(path("src"))),
      path: target,
    )

    #expect(missing.description == "the file 'src/Math.js' does not exist")
    #expect(spelled.description.contains("spelled differently on disk"))
    #expect(behind.description.contains("a symlink, which is never followed"))
  }

  @Test
  func `a path that names a folder, or cannot be read, says so`() throws {
    let target = try path("src")

    #expect(
      TransformerLinkProblem.file(.notAFile(.directory), path: target).description
        == "'src' is a folder, not a file",
    )
    #expect(
      TransformerLinkProblem.file(.notAFile(.other), path: target).description
        == "'src' is a pipe, socket or device, not a file",
    )
  }
}
