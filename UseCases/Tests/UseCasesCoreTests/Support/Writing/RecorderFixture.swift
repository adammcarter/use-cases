import Foundation
import Testing
@testable import UseCasesCore

/// A workspace on disk with a recorder over it: the real fingerprinter, the real writer, and a
/// clock and random source the test fixes.
struct RecorderFixture {
  let freshness: FreshnessFixture
  let recorder: VerdictRecorder

  var workspace: URL {
    freshness.workspace.directory.url
  }

  init(
    definitions: String = FreshnessSamples.definitions(),
    writing: Result<any RunWriting, StoreSchemaLoadingError>? = nil,
  ) throws {
    let clock = FixedTimekeeper()

    freshness = try FreshnessFixture(definitions: definitions)
    recorder = VerdictRecorder(
      fingerprinter: RouteFingerprintComputer(),
      writing: writing ?? Result { () throws(StoreSchemaLoadingError) in
        try RunWriter(
          clock: clock,
          random: FixedRandomBits(),
        )
      },
      reader: LocalAttachmentReader(),
      clock: clock,
    )
  }

  /// Plans a request against the workspace as it is on disk now.
  func plan(
    _ useCase: String,
    _ route: String,
    _ status: String = "pass",
    message: String? = nil,
    attachments: [URL] = [],
  ) throws -> RecordPlan {
    let loaded = try freshness.workspace.loaded()

    return try recorder.plan(
      RecordRequest(
        useCase: useCase,
        route: route,
        status: status,
        message: message,
        attachments: attachments,
      ),
      in: loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )
  }

  func readHistory() throws -> StoreHistory {
    try StoreReader().readHistory(in: workspace)
  }

  /// Whether the workspace has a results store at all.
  var hasStore: Bool {
    FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".use-cases").path)
  }
}
