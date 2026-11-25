import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The notes of a prune reach the person and the script.
struct PruneReportTests {
  private static let run = PrunableRun(
    identifier: "01a20e8224b8b82ea0fdc1e39430a016",
    bytes: 7812,
  )

  @Test
  func `a run kept with a note is told under the runs removed, and in the json`() throws {
    let report = PruneReport(
      removed: [Self.run],
      notes: ["run 01a20e8227b82ec00ca52da7c0ff9a9d is in use by another process, so it was kept"],
      isDryRun: false,
    )

    #expect(
      report.humanText().components(separatedBy: "\n") == [
        "removed  run 01a20e8224b8b82ea0fdc1e39430a016  7.8 KB",
        "note: run 01a20e8227b82ec00ca52da7c0ff9a9d is in use by another process, so it was kept",
        "",
        "removed 1 run · freed 7.8 KB",
      ],
    )
    #expect(
      try report.jsonText().contains(
        "\"run 01a20e8227b82ec00ca52da7c0ff9a9d is in use by another process, so it was kept\"",
      ),
    )
  }

  @Test(arguments: [(false, "removed"), (true, "would remove")])
  func `a leftover is listed on its own line and counted beside the runs`(
    isDryRun: Bool,
    verb: String,
  ) throws {
    let report = PruneReport(
      removed: [Self.run],
      leftovers: [
        PruneLeftover(
          location: ".use-cases/runs/.tmp-prune-01a20e8227b82ec00ca52da7c0ff9a9d",
          bytes: 188,
        ),
      ],
      notes: [],
      isDryRun: isDryRun,
    )
    let freed = isDryRun ? "would free" : "freed"

    #expect(
      report.humanText().components(separatedBy: "\n") == [
        "\(verb)  run 01a20e8224b8b82ea0fdc1e39430a016  7.8 KB",
        "\(verb) leftover  .use-cases/runs/.tmp-prune-01a20e8227b82ec00ca52da7c0ff9a9d  188 B",
        "",
        "\(verb) 1 run, 1 leftover · \(freed) 8.0 KB",
      ],
    )

    let schema = try PublishedSchema(path: "schemas/output/cli-prune.schema.json")
    let document = try JSONDecoder().decode(JSONValue.self, from: Data(report.jsonText().utf8))

    #expect(try schema.failures(of: document) == [])
    #expect(document["bytes"] == .integer(8000))
  }

  @Test
  func `runs kept are counted in the total, never nothing to prune`() throws {
    let report = PruneReport(
      removed: [],
      kept: [Self.run],
      notes: ["run 01a20e8224b8b82ea0fdc1e39430a016 is in use by another process, so it was kept"],
      isDryRun: false,
    )

    #expect(
      report.humanText().components(separatedBy: "\n") == [
        "note: run 01a20e8224b8b82ea0fdc1e39430a016 is in use by another process, so it was kept",
        "",
        "kept 1 run",
      ],
    )

    let document = try JSONDecoder().decode(JSONValue.self, from: Data(report.jsonText().utf8))
    let schema = try PublishedSchema(path: "schemas/output/cli-prune.schema.json")

    #expect(try schema.failures(of: document) == [])
    #expect(document["bytes"] == .integer(0))
  }

  @Test
  func `a run left over is counted apart, and its space is not freed`() throws {
    let report = PruneReport(
      removed: [Self.run],
      leftOver: [
        PruneLeftover(
          location: ".use-cases/runs/.tmp-prune-01a20e8227b82ec00ca52da7c0ff9a9d",
          bytes: 5000,
        ),
      ],
      notes: [],
      isDryRun: false,
    )

    #expect(report.humanText().components(separatedBy: "\n").last
      == "removed 1 run · freed 7.8 KB · 1 run left over")
    #expect(report.bytes == 7812)

    let document = try JSONDecoder().decode(JSONValue.self, from: Data(report.jsonText().utf8))
    let schema = try PublishedSchema(path: "schemas/output/cli-prune.schema.json")

    #expect(try schema.failures(of: document) == [])
  }

  @Test
  func `nothing removed with a note says nothing to prune, then the note`() {
    let report = PruneReport(
      removed: [],
      notes: ["run 01a20e8224b8b82ea0fdc1e39430a016 was kept: no such folder"],
      isDryRun: false,
    )

    #expect(
      report.humanText().components(separatedBy: "\n") == [
        "nothing to prune",
        "note: run 01a20e8224b8b82ea0fdc1e39430a016 was kept: no such folder",
      ],
    )
  }
}
