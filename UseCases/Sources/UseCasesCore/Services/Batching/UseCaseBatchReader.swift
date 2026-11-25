import Foundation

/// Reads a batch as a YAML or JSON mapping. The keys of a proposal file that `apply` ignores
/// (chapter 21 §7) are accepted and their values never looked at, so the file the person signed
/// off is the file applied.
struct UseCaseBatchReader: UseCaseBatchReading {
  /// The keys of a proposal file beside `remove` and `save`.
  static let proposalKeys = ["title", "untouched", "fits", "you_see", "decisions", "golden"]

  private static let removeKey = "remove"
  private static let saveKey = "save"

  private let reader: any AuthoredInputReading
  private let checker: any UseCaseInputChecking

  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  init(workingDirectory: URL) {
    self.init(
      reader: AuthoredInputReader(workingDirectory: workingDirectory),
      checker: UseCaseInputChecker(),
    )
  }

  init(
    reader: any AuthoredInputReading,
    checker: any UseCaseInputChecking,
  ) {
    self.reader = reader
    self.checker = checker
  }

  func read(_ argument: String) throws(UseCaseBatchError) -> UseCaseBatch {
    let input: AuthoredInput

    do {
      input = try reader.read(AuthoredInputSource(argument: argument))
    } catch {
      throw .input(message: error.message)
    }

    return try batch(from: input)
  }

  func batch(from input: AuthoredInput) throws(UseCaseBatchError) -> UseCaseBatch {
    guard let object = try? AuthoredObject(input.value, at: "") else {
      throw .notABatch(
        name: input.name,
        problem: nil,
      )
    }

    if let stranger = object.members.first(where: { member in
      !Self.isKey(member.key)
    }) {
      throw .notABatch(
        name: input.name,
        problem: "'\(stranger.key)' is not a key of a batch",
      )
    }

    let removals = try removals(
      of: object,
      named: input.name,
    )
    let saves = try saves(
      of: object,
      named: input.name,
    )

    guard !removals.isEmpty || !saves.isEmpty else {
      throw .notABatch(
        name: input.name,
        problem: "this one changes nothing",
      )
    }

    return UseCaseBatch(
      removals: removals,
      saves: saves,
    )
  }

  private func removals(
    of object: AuthoredObject,
    named name: String,
  ) throws(UseCaseBatchError) -> [String] {
    guard let value = object.value(for: Self.removeKey), value != .null else {
      return []
    }

    guard case let .array(items) = value else {
      throw .removeNotIds(name: name)
    }

    var identifiers: [String] = []

    for item in items {
      guard case let .string(identifier) = item else {
        throw .removeNotIds(name: name)
      }

      identifiers.append(identifier)
    }

    return identifiers
  }

  private func saves(
    of object: AuthoredObject,
    named name: String,
  ) throws(UseCaseBatchError) -> [CheckedUseCase] {
    guard let value = object.value(for: Self.saveKey), value != .null else {
      return []
    }

    guard case let .array(items) = value else {
      throw .saveNotUseCases(name: name)
    }

    var checked: [CheckedUseCase] = []

    for (number, item) in items.enumerated() {
      do {
        try checked.append(
          checker.check(
            AuthoredInput(
              name: "\(name) save[\(number)]",
              value: item,
            ),
          ),
        )
      } catch {
        throw .editing(error)
      }
    }

    return checked
  }

  private static func isKey(_ key: String) -> Bool {
    ([removeKey, saveKey] + proposalKeys).contains { known in
      known.isExactlyEqual(to: key)
    }
  }
}
