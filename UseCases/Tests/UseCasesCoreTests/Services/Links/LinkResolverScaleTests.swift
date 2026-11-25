import Foundation
import Testing
@testable import UseCasesCore

struct LinkResolverScaleTests {
  private static let areas = 50
  private static let perArea = 20
  private static let testsPerCase = 3

  /// The work is counted, not timed: a resolver that went over the files again for each use case
  /// or each marker would read a file a thousand times, and one that reads each file once
  /// cannot be quadratic in the files.
  @Test
  func `a thousand use cases and four thousand markers read each file once`() throws {
    let fixture =
      try WorkspaceFixture(rootConfiguration: "schema_version: 1\nroot: true\nprefix: shop\n")

    for area in 0 ..< Self.areas {
      try write(area: area, to: fixture)
    }

    let logs = try TemporaryDirectory()
    let counting = try CountingFileSystem(log: logs.location(of: "reads.log"))
    let workspace = try fixture.loaded()

    let resolution = LinkResolver(
      codeScanner: CodeScanner(
        fileSystem: counting,
        markerScanner: MarkerScanner(),
      ),
      markerLinker: MarkerLinker(),
      bindingResolver: ManualBindingResolver(
        fileSystem: counting,
        pathFinder: ExactPathFinder(fileSystem: counting),
        rangeConverter: ManualRangeConverter(),
      ),
      conflictFinder: LinkConflictFinder(),
    ).resolveLinks(in: workspace)

    let reads = try counting.reads()
    let expected = Self.areas * Self.perArea * (1 + Self.testsPerCase)

    #expect(resolution.links.count == expected)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warningLines.isEmpty)
    #expect(reads.count == 2 * Self.areas)
    #expect(reads.values.allSatisfy { $0 == 1 })
  }

  private func write(
    area: Int,
    to fixture: WorkspaceFixture,
  ) throws {
    let name = "area\(String(format: "%02d", area))"
    var definitions = "prefix: \(name)\nuse_cases:\n"
    var source = ""
    var tests = ""

    for index in 0 ..< Self.perArea {
      let local = "rule\(String(format: "%02d", index))"
      let full = "shop.\(name).\(local)"

      definitions += YAMLSamples.useCase(local)
      source += LinkSamples.marked("\(full)#logic", "def \(local)(x): return x + \(index)") + "\n"

      for number in 0 ..< Self.testsPerCase {
        let id = "\(full)#manual.t\(number)"
        tests += LinkSamples.marked(id, "assert \(local)(\(number))") + "\n"
      }
    }

    try fixture.write("use-cases/\(name).yml", definitions)
    try fixture.write("src/shop/\(name).py", source)
    try fixture.write("tests/test_\(name).py", tests)
  }
}
