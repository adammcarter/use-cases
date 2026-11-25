import Foundation
import Testing
@testable import UseCasesCore

/// A real workspace folder holding a results store that tests build run by run, with the digests
/// a sealed run carries worked out from the real bytes. It writes by hand what the core's writers
/// will write, so the reader is held to the chapter and not to the writer.
final class StoreFixture {
  let directory: TemporaryDirectory
  private let hasher = SHA256Hasher()

  var workspace: URL {
    directory.url
  }

  init() throws {
    directory = try TemporaryDirectory()
  }

  /// A run id for a small number, written at full width.
  static func identifier(_ number: Int) -> String {
    let hex = String(number, radix: 16)

    return String(repeating: "0", count: 32 - hex.count) + hex
  }

  /// The place of a run's folder, relative to the workspace.
  static func folder(_ identifier: String) -> String {
    ".use-cases/runs/\(identifier)"
  }

  func digest(of text: String) -> String {
    hasher.sha256Hex(of: Array(text.utf8))
  }

  func write(
    _ path: String,
    _ text: String,
  ) throws {
    try directory.write(path, text)
  }

  func read(_ path: String) throws -> String {
    try String(contentsOf: directory.location(of: path), encoding: .utf8)
  }

  /// Writes a sealed run: manifest, log, optional start stamp, outputs, reports and attachments,
  /// then the marker that digests them.
  ///
  /// - Parameters:
  ///   - results: One member set per line of the log.
  ///   - start: The start stamp. A verify run always has one, so it gets the sample's if none is
  ///     given.
  ///   - outputs: Console captures by path under `outputs/`.
  ///   - reports: Report files by path under `reports/`.
  ///   - blobs: Attachment bytes by the digest they are kept under.
  ///   - marker: Members of the marker to set before it is written.
  ///   - markerWithout: Members of the marker to leave out.
  func sealRun(
    _ identifier: String,
    kind: String = "record",
    results: [JSONMembers]? = nil,
    start: JSONMembers? = nil,
    outputs: [String: String] = [:],
    reports: [String: String] = [:],
    blobs: [String: String] = [:],
    marker: [String: String] = [:],
    markerWithout: [String] = [],
  ) throws {
    let folder = Self.folder(identifier)
    let lines = results ?? [StoreSamples.recordedResult()]
    let manifestText = StoreSamples.manifest(
      runIdentifier: identifier,
      kind: kind,
    ).json
    let logText = lines.map { $0.json + "\n" }.joined()

    try write("\(folder)/run.json", manifestText)
    try write("\(folder)/results.jsonl", logText)

    var completion = StoreSamples.completion(
      runIdentifier: identifier,
      resultCount: lines.count,
      manifestDigest: digest(of: manifestText),
      resultsDigest: digest(of: logText),
    )
    completion = try completion
      .setting("outputs_sha256", digests(outputs, under: "\(folder)/outputs"))
      .setting("reports_sha256", digests(reports, under: "\(folder)/reports"))
    if let stamp = start ?? (kind == "verify" ? StoreSamples.start : nil) {
      try write("\(folder)/start.json", stamp.json)
      completion = completion.setting("start_sha256", StoreSamples.quoted(digest(of: stamp.json)))
    }
    for (blobDigest, content) in blobs {
      try write("\(folder)/\(StoreLayout.attachmentPath(digest: blobDigest))", content)
    }

    for (name, value) in marker {
      completion = completion.setting(name, value)
    }
    for name in markerWithout {
      completion = completion.removing(name)
    }

    try write("\(folder)/completion.json", completion.json)
  }

  /// Reads the store and returns what is wrong with it, as the messages say it.
  func problems() throws -> [String] {
    let error = #expect(throws: StoreReadingError.self) {
      try StoreReader().readHistory(in: workspace)
    }

    guard case let .damaged(found)? = error else {
      Issue.record("expected a storage error, got \(String(describing: error))")
      return []
    }

    return found.map(\.description)
  }

  /// A sealed record run with one result.
  func sealRecord(
    _ identifier: String,
    useCase: String = StoreSamples.useCase,
    route: String = StoreSamples.route,
    fingerprint: String = StoreSamples.fingerprint,
    status: String = "pass",
  ) throws {
    try sealRun(
      identifier,
      results: [StoreSamples.recordedResult(
        useCase: useCase,
        route: route,
        fingerprint: fingerprint,
        status: status,
      )],
    )
  }

  /// A run folder with the files an unfinished run has and no marker.
  func startRun(_ identifier: String) throws {
    let folder = Self.folder(identifier)

    try write("\(folder)/run.json", StoreSamples.manifest(runIdentifier: identifier).json)
    try write("\(folder)/results.jsonl", "")
  }

  /// The members of a digest map: each file is written, then listed with its digest.
  private func digests(
    _ files: [String: String],
    under folder: String,
  ) throws -> String {
    var members: [String] = []

    for path in files.keys.sorted() {
      let content = files[path] ?? ""
      try write("\(folder)/\(path)", content)
      members.append("\(StoreSamples.quoted(path)):\(StoreSamples.quoted(digest(of: content)))")
    }

    return "{" +
      members.joined(separator: ",") +
      "}"
  }
}
