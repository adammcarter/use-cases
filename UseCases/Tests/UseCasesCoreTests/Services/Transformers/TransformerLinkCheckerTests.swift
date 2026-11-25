import Foundation
import Testing
@testable import UseCasesCore

struct TransformerLinkCheckerTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture(
      rootConfiguration: YAMLSamples.root + "discovery:\n  exclude: [vendor]\n",
    )
    try fixture.writeUseCase()
    try fixture.write("src/math.js", "one\ntwo\nthree\n")
    try fixture.write("src/empty.txt", "")
    try fixture.write("src/binary.dat", bytes: [0xFF, 0xFE, 0x00, 0x0A, 0x41])
    try fixture.write("vendor/lib.js", "x\n")
    try fixture.directory.symlink("src/alias.js", to: "math.js")
  }

  private func resolve(_ link: TransformerLink) throws -> ResolvedLink {
    let workspace = try fixture.loaded()
    var files = BoundFiles()
    let fileSystem = LocalFileSystem()

    return try TransformerLinkChecker(
      placer: ManualBindingResolver(
        fileSystem: fileSystem,
        pathFinder: ExactPathFinder(fileSystem: fileSystem),
        rangeConverter: ManualRangeConverter(),
      ),
    ).resolve(
      link,
      from: "tools/links",
      among: LinkTargets(workspace.useCases),
      context: workspace.discoveryContext,
      files: &files,
    )
  }

  private func bad(_ problem: TransformerLinkProblem) -> TransformerError {
    .badLink(
      name: "tools/links",
      link: "{}",
      problem: problem,
    )
  }

  // MARK: - Links that stand

  @Test
  func `an implementation link with no range covers the whole file`() throws {
    let link = try resolve(.sample())

    #expect(link.source == .transformer)
    #expect(link.useCase == "app.toggle")
    #expect(link.route == nil)
    #expect(link.binding == "render")
    #expect(link.role == .implementation)
    #expect(link.file == "src/math.js")
    #expect(link.startLine == 1)
    #expect(link.endLine == 3)
    #expect(link.span == 0 ..< 14)
    #expect(link.contentRanges == [0 ..< 14])
    #expect(link.key == "app.toggle#render@src/math.js:1")
  }

  @Test
  func `a validation link names its route and the lines of the test`() throws {
    let link = try resolve(
      .sample(
        route: "manual",
        role: "validation",
        range: TransformerLinkRange(start: 2, end: 3),
      ),
    )

    #expect(link.role == .validation)
    #expect(link.route == "manual")
    #expect(link.startLine == 2)
    #expect(link.endLine == 3)
    #expect(link.span == 4 ..< 14)
    #expect(link.key == "app.toggle#manual.render@src/math.js:2")
  }

  @Test(arguments: [(1, 1, 0 ..< 4), (2, 2, 4 ..< 8), (3, 3, 8 ..< 14), (1, 2, 0 ..< 8)])
  func `lines are whole lines, each with its line break`(
    start: Int,
    end: Int,
    span: Range<Int>,
  ) throws {
    let link = try resolve(.sample(range: TransformerLinkRange(start: start, end: end)))

    #expect(link.span == span)
  }

  @Test
  func `an empty file is line 1 to line 1 and holds nothing`() throws {
    let link = try resolve(.sample(file: "src/empty.txt"))

    #expect(link.startLine == 1)
    #expect(link.endLine == 1)
    #expect(link.span.isEmpty)
    #expect(link.contentRanges.isEmpty)
  }

  @Test
  func `a file that is not text may be linked whole`() throws {
    let link = try resolve(.sample(file: "src/binary.dat"))

    #expect(link.span == 0 ..< 5)
  }

  @Test
  func `a symlink is never followed: the link holds the text it points with`() throws {
    let link = try resolve(.sample(file: "src/alias.js"))

    #expect(link.span == 0 ..< 7)
  }

  // MARK: - Links that do not

  @Test(
    arguments: [
      (TransformerLink.sample(useCase: nil), TransformerLinkProblem.missingMember("use_case")),
      (.sample(role: nil), .missingMember("role")),
      (.sample(binding: nil), .missingMember("binding")),
      (.sample(file: nil), .missingMember("file")),
      (.sample(useCase: "app.nope"), .unknownUseCase("app.nope")),
      (.sample(useCase: "Not An Id"), .unknownUseCase("Not An Id")),
      (.sample(useCase: ""), .unknownUseCase("")),
      (.sample(role: "both"), .unknownRole("both")),
      (.sample(role: "Validation"), .unknownRole("Validation")),
      (.sample(binding: "Bad Binding"), .invalidBinding("Bad Binding")),
      (.sample(binding: ""), .invalidBinding("")),
      (.sample(role: "validation"), .validationNeedsRoute),
      (
        .sample(route: "nope", role: "validation"),
        .unknownRoute(route: "nope", useCase: "app.toggle"),
      ),
      (.sample(route: "manual"), .implementationHasRoute("manual")),
      (.sample(route: "nope"), .implementationHasRoute("nope")),
    ],
  )
  func `a link that is not whose it says it is, or is not a link at all, is bad`(
    link: TransformerLink,
    problem: TransformerLinkProblem,
  ) {
    #expect(throws: bad(problem)) {
      try resolve(link)
    }
  }

  @Test(
    arguments: [
      ("../outside.js", WorkspacePathError.parentSegment("../outside.js")),
      ("src/../../x", .parentSegment("src/../../x")),
      ("/etc/passwd", .absolute("/etc/passwd")),
      ("C:/x", .driveLetter("C:/x")),
      ("src\\math.js", .backslash("src\\math.js")),
      ("", .empty),
    ],
  )
  func `a file that is not a path inside the project is bad`(
    file: String,
    error: WorkspacePathError,
  ) {
    #expect(throws: bad(.fileOutsideProject(error))) {
      try resolve(.sample(file: file))
    }
  }

  @Test
  func `the workspace root is not a file`() throws {
    let root = try WorkspacePath(validating: ".")

    #expect(throws: bad(.file(.notAFile(.directory), path: root))) {
      try resolve(.sample(file: "."))
    }
  }

  @Test(arguments: [(".git/HEAD", true), ("vendor/lib.js", false), ("vendor/missing.js", false)])
  func `a file in an excluded folder is bad, whether the exclusion is built in or the workspace's`(
    file: String,
    isBuiltIn: Bool,
  ) throws {
    let error = #expect(throws: TransformerError.self) {
      try resolve(.sample(file: file))
    }

    guard case let .badLink(_, _, .fileExcluded(exclusion))? = error else {
      Issue.record("not an exclusion: \(String(describing: error))")
      return
    }

    #expect(exclusion.isBuiltIn == isBuiltIn)
  }

  @Test
  func `a file that is not there is bad`() throws {
    let missing = try WorkspacePath(validating: "src/missing.js")

    #expect(throws: bad(.file(.path(.missing), path: missing))) {
      try resolve(.sample(file: "src/missing.js"))
    }
  }

  @Test
  func `a file spelled in another case than on disk is bad, whatever the file system`() throws {
    let wrong = try WorkspacePath(validating: "src/Math.js")
    let problem = TransformerLinkProblem.file(
      .path(.spelledDifferently(written: "Math.js", onDisk: "math.js")),
      path: wrong,
    )

    #expect(throws: bad(problem)) {
      try resolve(.sample(file: "src/Math.js"))
    }
  }

  @Test
  func `a folder is not a file`() throws {
    let folder = try WorkspacePath(validating: "src")

    #expect(throws: bad(.file(.notAFile(.directory), path: folder))) {
      try resolve(.sample(file: "src"))
    }
  }

  @Test
  func `a path through a symlinked folder is bad`() throws {
    try fixture.directory.symlink("linked", to: "src")

    let error = #expect(throws: TransformerError.self) {
      try resolve(.sample(file: "linked/math.js"))
    }

    guard case .badLink(_, _, .file(.path(.behindSymlink), _))? = error else {
      Issue.record("not a symlink: \(String(describing: error))")
      return
    }
  }

  @Test(
    arguments: [
      TransformerLinkRange(start: nil, end: nil),
      TransformerLinkRange(start: 1, end: nil),
      TransformerLinkRange(start: nil, end: 2),
      TransformerLinkRange(start: 0, end: 2),
      TransformerLinkRange(start: 1, end: 0),
      TransformerLinkRange(start: -3, end: 2),
    ],
  )
  func `a range that is not two lines counted from 1 is bad`(range: TransformerLinkRange) {
    #expect(throws: bad(.rangeNotLines)) {
      try resolve(.sample(range: range))
    }
  }

  @Test(arguments: [(1, 4, 4, 3), (2, 99, 99, 3), (4, 4, 4, 3), (99, 99, 99, 3)])
  func `a range outside the file is bad, and says how long the file is`(
    start: Int,
    end: Int,
    line: Int,
    count: Int,
  ) throws {
    let path = try WorkspacePath(validating: "src/math.js")
    let problem = TransformerLinkProblem.range(
      .lineOutsideFile(line: line, lineCount: count),
      path: path,
    )

    #expect(throws: bad(problem)) {
      try resolve(.sample(range: TransformerLinkRange(start: start, end: end)))
    }
  }

  @Test
  func `a range that starts after it ends is bad`() throws {
    let path = try WorkspacePath(validating: "src/math.js")

    #expect(throws: bad(.range(.startsAfterEnd, path: path))) {
      try resolve(.sample(range: TransformerLinkRange(start: 3, end: 1)))
    }
  }

  @Test
  func `a range cannot be cut from a file that is not text`() throws {
    let path = try WorkspacePath(validating: "src/binary.dat")

    #expect(throws: bad(.range(.notText, path: path))) {
      try resolve(.sample(file: "src/binary.dat", range: TransformerLinkRange(start: 1, end: 1)))
    }
  }

  @Test
  func `the first thing wrong is the one told: whose the link is comes before where it points`()
    throws
  {
    let link = TransformerLink.sample(
      useCase: "app.nope",
      binding: "Bad Binding",
      file: "../outside.js",
    )

    #expect(throws: bad(.unknownUseCase("app.nope"))) {
      try resolve(link)
    }
  }

  @Test
  func `the error carries the link as it came, so a person can find it`() {
    let link = TransformerLink(
      useCase: "app.nope",
      route: nil,
      binding: "t",
      role: "implementation",
      file: "a.js",
      range: nil,
      text: #"{"binding":"t","file":"a.js"}"#,
    )

    #expect(
      throws: TransformerError.badLink(
        name: "tools/links",
        link: #"{"binding":"t","file":"a.js"}"#,
        problem: .unknownUseCase("app.nope"),
      ),
    ) {
      try resolve(link)
    }
  }
}
