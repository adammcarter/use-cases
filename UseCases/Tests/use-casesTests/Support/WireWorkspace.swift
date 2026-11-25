import Foundation
import UseCasesTestSupport

/// A workspace on disk for the built program to work in: made from the files a test names, and
/// removed when it is done.
struct WireWorkspace {
  /// The folder, by its real path.
  let folder: URL

  /// Makes a folder holding `files`, by relative path.
  init(files: [String: String]) throws {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "use-cases-wire-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: folder,
      withIntermediateDirectories: true,
    )
    try self.init(
      files: files,
      in: folder.resolvingSymlinksInPath(),
    )
  }

  /// Writes `files`, by relative path, into `folder`, which exists and is named by its real path.
  private init(
    files: [String: String],
    in folder: URL,
  ) throws {
    self.folder = folder

    for (path, text) in files {
      let file = self.folder.appending(path: path)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true,
      )
      try text.write(
        to: file,
        atomically: true,
        encoding: .utf8,
      )
    }
  }

  func remove() {
    try? FileManager.default.removeItem(at: folder)
  }

  /// A workspace of `count` use cases, each with a long description, so that a search of it that
  /// asks for the whole use cases answers hundreds of kilobytes.
  static func big(count: Int) throws -> WireWorkspace {
    let description = String(repeating: "lorem ipsum dolor sit amet ", count: 30)
    let cases = (0 ..< count).map { number in
      """
        - id: case-\(number)
          title: Big case number \(number) with ünïcödé ✓
          description: "\(description)"
      """
    }

    return try WireWorkspace(
      files: [
        "use-cases.yml": "schema_version: 1\nroot: true\nprefix: big\n",
        "use-cases/big.yml": "prefix: big\n\nuse_cases:\n" + cases.joined(separator: "\n") + "\n",
      ],
    )
  }

  /// A workspace with one use case, whose test is the script `script` makes, run by
  /// `verify --run`, and the hold the script can wait on: `script` is given the hold, whose
  /// shell text holds the test there until the hold is released.
  static func verifying(
    script: (_ hold: ChildHold) -> String,
  ) throws -> (workspace: WireWorkspace, hold: ChildHold) {
    let folder = try WireWorkspace(files: [:]).folder
    let hold = try ChildHold(at: folder.appending(path: "hold.fifo"))
    var files = verifyingFiles
    files["slow.sh"] = script(hold) + "\n"
    let workspace = try WireWorkspace(
      files: files,
      in: folder,
    )

    return (workspace, hold)
  }

  /// The files of a verifying workspace but its test script, `slow.sh`.
  private static let verifyingFiles: [String: String] = [
    "use-cases.yml": """
    schema_version: 1
    root: true
    prefix: duration
    use_cases_dir: use-cases

    """,
    "use-cases/text.yml": """
    prefix: text

    use_cases:
      - id: parse
        title: Read a human duration
        value_tier: core
        intent: People can type durations like "1h 30m" and get exact milliseconds.
        scenarios:
          - id: adds-units
            when: ['"1h 30m" is parsed.']
            then: ["The result is 5,400,000 ms."]
        validation:
          - id: unit-tests
            type: { kind: unit }
            covers: [adds-units]

    """,
    "use-cases-bridge.yml": """
    schema_version: 1

    validations:
      - id: slow-test
        report: slow-test.txt
        run: [sh, ./slow.sh]
        transformer: exit-code
        settings:
          file: test/slow.test.sh

    """,
    "test/slow.test.sh": """
    # @use-case:duration.text.parse#unit-tests.adds-units
    true
    # @use-case:end duration.text.parse#unit-tests.adds-units

    """,
  ]

  /// The names of the runs the program has stored that were never sealed.
  func unsealedRuns() -> [String] {
    var unsealed: [String] = []

    for run in runs() where !run.isSealed {
      unsealed.append(run.name)
    }

    return unsealed
  }

  /// The runs the program has stored, each with whether it was sealed.
  func runs() -> [(name: String, isSealed: Bool)] {
    let runs = folder.appending(path: ".use-cases/runs")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? []

    return names.sorted().map { name in
      (
        name,
        FileManager.default.fileExists(
          atPath: runs.appending(path: "\(name)/completion.json").path,
        ),
      )
    }
  }
}
