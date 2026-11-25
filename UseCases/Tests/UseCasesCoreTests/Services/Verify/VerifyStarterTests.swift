import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct VerifyStarterTests {
  private static let twoValidations =
    BridgeFileSamples.validation(lines: ["report: unit.xml"])
      + "  - id: style\n    report: style.txt\n    transformer: exit-code\n"

  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  @Test
  func `a start opens a run with its start stamp and an empty reports folder`() throws {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)
    let folder = ".use-cases/runs/\(run)"

    #expect(started.isStarted)
    #expect(started.selected == ["unit-tests"])
    #expect(
      started.reports == [
        StartedReport(
          validation: "unit-tests",
          path: fixture.workspace.path + "/\(folder)/reports/unit-tests/unit.xml",
        ),
      ],
    )
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.freshness.workspace.directory.location(of: "\(folder)/reports/unit-tests")
          .path,
      ),
    )
    #expect(try fixture.read("\(folder)/start.json").contains("\"opened_by\": \"start\""))
  }

  @Test
  func `the run is open: it is listed as never finished and is no evidence`() throws {
    let started = try fixture.start()
    let history = try fixture.history()

    #expect(history.runs.isEmpty)
    #expect(history.unfinishedRuns.map(\.identifier.text) == [started.runIdentifier])
  }

  @Test
  func `the manifest plans the sources of the selected validations`() throws {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)
    let manifest = try fixture.read(".use-cases/runs/\(run)/run.json")

    #expect(manifest.contains("\"report\": \"reports/unit-tests/unit.xml\""))
    #expect(manifest.contains("\"transformer\": \"junit\""))
    #expect(manifest.contains("\"kind\": \"verify\""))
  }

  @Test
  func `the stamp notes every route's fingerprint and every linked file`() throws {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)
    let stamp = try fixture.read(".use-cases/runs/\(run)/start.json")
    let fingerprint = try fixture.freshness.fingerprint(of: "unit-tests")

    #expect(stamp.contains(fingerprint))
    #expect(stamp.contains("\"\(VerifyFixture.codeFile)\""))
    #expect(stamp.contains("\"\(VerifyFixture.testFile)\""))
  }

  @Test
  func `only selects validations, in the order of the settings, and makes folders for those`()
    throws
  {
    let two = try VerifyFixture(bridge: Self.twoValidations)

    let started = try two.start(only: ["style"])
    let run = try #require(started.runIdentifier)

    #expect(started.selected == ["style"])
    #expect(started.reports.map(\.validation) == ["style"])
    #expect(two.freshness.workspace.directory.location(of: ".use-cases/runs/\(run)/reports").path
      .isDirectory(containing: ["style"]))
  }

  @Test
  func `without only every validation is read, in the order of the settings`() throws {
    let two = try VerifyFixture(bridge: Self.twoValidations)

    #expect(try two.start().selected == ["unit-tests", "style"])
    #expect(try two.start(only: ["style", "unit-tests"]).selected == ["unit-tests", "style"])
  }

  @Test
  func `a validation the settings do not have is refused before any run is written`() throws {
    let two = try VerifyFixture(bridge: Self.twoValidations)

    #expect(
      throws: VerifyError.unknownValidations(
        ["nope"],
        known: ["unit-tests", "style"],
      ),
    ) {
      try two.start(only: ["unit-tests", "nope"])
    }
    #expect(two.runs().isEmpty)
  }

  @Test
  func `a start says what else is open, and closes nothing`() throws {
    let first = try fixture.start()
    let second = try fixture.start()
    let last = try #require(second.notes.last)

    #expect(try last.contains(#require(first.runIdentifier)))
    #expect(second.notes.count == 2)
    #expect(try fixture.history().unfinishedRuns.count == 2)
  }

  @Test
  func `a start with no other run open says only what to do next`() throws {
    let started = try fixture.start()
    let run = try #require(started.runIdentifier)

    #expect(started.notes.count == 1)
    #expect(started.notes[0].contains("--finish --run-id \(run)"))
  }

  @Test
  func `no bridge settings or no validations start nothing and write nothing`() throws {
    for bridge in [nil, "schema_version: 1\nvalidations: []\n"] {
      let bare = try VerifyFixture(bridge: bridge)

      let started = try bare.start()

      #expect(!started.isStarted)
      #expect(started.runIdentifier == nil)
      #expect(started.notes.first?.contains("nothing to start") == true)
      #expect(bare.runs().isEmpty)
    }
  }

  @Test
  func `a workspace whose fingerprints cannot be known is refused`() throws {
    let broken = try VerifyFixture(
      definitions: FreshnessSamples.definitions(
        resources: [FreshnessSamples.file("fixtures/missing.json")],
      ),
    )

    #expect(throws: VerifyError.self) {
      try broken.start()
    }
    #expect(broken.runs().isEmpty)
  }
}

private extension String {
  /// Whether the folder at this path holds exactly these names.
  func isDirectory(containing names: [String]) -> Bool {
    let found = (try? FileManager.default.contentsOfDirectory(atPath: self)) ?? []

    return found.sorted() == names.sorted()
  }
}
