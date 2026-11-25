import Foundation
import Testing
@testable import UseCasesCore

/// A run that `prune` takes away while a reader is reading the store is gone whole: never damaged,
/// never unfinished (chapter 12 §30). The file system below removes the run at a set moment of the
/// read, so no timing is involved.
struct StoreReaderVanishingRunTests {
  /// When, during the read, the run leaves `runs/`.
  enum Moment: Sendable, CaseIterable {
    /// Just after `runs/` is listed.
    case afterListing

    /// Just after the run's completion marker was read, before its manifest.
    case afterMarker

    /// After the marker and the log were read, just before a report's digest is checked: the
    /// read would come back sealed, with the report missing.
    case beforeReport
  }

  /// The real file system, which moves one run's folder out of `runs/` at the moment given.
  private struct VanishingFileSystem: FileSystemReading {
    let run: URL
    let moment: Moment
    private let local = LocalFileSystem()

    init(
      run: URL,
      moment: Moment,
    ) {
      self.run = run
      self.moment = moment
    }

    private func vanish() {
      let aside = run.deletingLastPathComponent()
        .appendingPathComponent(".tmp-prune-" + run.lastPathComponent)
      try? FileManager.default.moveItem(
        at: run,
        to: aside,
      )
    }

    func canonicalLocation(of url: URL) -> URL {
      local.canonicalLocation(of: url)
    }

    func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
      vanishIfReport(url)

      return try local.kindOfItem(at: url)
    }

    /// The run leaves as soon as anything under its `reports/` is looked at.
    private func vanishIfReport(_ url: URL) {
      if moment == .beforeReport, url.path.hasPrefix(run.appendingPathComponent("reports").path) {
        vanish()
      }
    }

    func chunks(of file: URL) throws(FileSystemError) -> any FileChunkReading {
      vanishIfReport(file)

      return try local.chunks(of: file)
    }

    func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
      let found = try local.entries(in: folder)

      if moment == .afterListing, folder.lastPathComponent == "runs" {
        vanish()
      }

      return found
    }

    func readText(at file: URL) throws(FileSystemError) -> String {
      try local.readText(at: file)
    }

    func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
      vanishIfReport(file)
      let bytes = try local.readBytes(at: file)

      if moment == .afterMarker, file.path == run.appendingPathComponent("completion.json").path {
        vanish()
      }

      return bytes
    }

    func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
      try local.targetText(ofSymlinkAt: link)
    }

    func holdsFile(
      named name: String,
      below folder: FileEntry,
      in parent: URL,
    ) -> Bool {
      local.holdsFile(
        named: name,
        below: folder,
        in: parent,
      )
    }
  }

  @Test(arguments: Moment.allCases)
  func `a run taken away during the read is passed over, and the rest reads clean`(
    moment: Moment,
  ) throws {
    let store = try StoreFixture()
    let older = StoreFixture.identifier(1)
    let newer = StoreFixture.identifier(2)
    try store.sealRun(
      older,
      kind: "verify",
      reports: ["unit-tests/report.xml": "<testsuites/>\n"],
    )
    try store.sealRecord(newer)
    let run = store.workspace.appendingPathComponent(StoreFixture.folder(older))

    let history = try StoreReader(
      fileSystem: VanishingFileSystem(
        run: run,
        moment: moment,
      ),
    ).readHistory(in: store.workspace)

    #expect(history.runs.map(\.identifier.text) == [newer])
    #expect(history.unfinishedRuns.isEmpty)
    #expect(history.findings.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: run.path))
  }

  @Test
  func `a run with a file missing that is still there is damaged, as before`() throws {
    let store = try StoreFixture()
    try store.sealRecord(StoreFixture.identifier(1))
    try FileManager.default.removeItem(
      at: store.workspace
        .appendingPathComponent(StoreFixture.folder(StoreFixture.identifier(1)))
        .appendingPathComponent("run.json"),
    )

    #expect(try !store.problems().isEmpty)
  }
}
