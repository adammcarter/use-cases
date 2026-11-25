import Testing
@testable import UseCasesCore

/// The authored-schema samples of `docs/schemas/engine/validate.py`, each with the verdict
/// that script expects.
struct AuthoredSchemaSamplesTests {
  @Test(arguments: UseCaseSamples.all)
  func `a use-case sample gets the verdict validate.py expects`(
    sample: AuthoredSchemaSample,
  ) throws {
    try expectVerdict(of: sample)
  }

  @Test(arguments: WorkspaceSamples.all)
  func `a workspace sample gets the verdict validate.py expects`(
    sample: AuthoredSchemaSample,
  ) throws {
    try expectVerdict(of: sample)
  }

  @Test(arguments: BridgeSamples.all)
  func `a bridge sample gets the verdict validate.py expects`(
    sample: AuthoredSchemaSample,
  ) throws {
    try expectVerdict(of: sample)
  }

  @Test(arguments: LineSeparatorSamples.all)
  func `a path hiding dot dot behind a line separator is refused`(
    sample: AuthoredSchemaSample,
  ) throws {
    try expectVerdict(of: sample)
  }

  private func expectVerdict(of sample: AuthoredSchemaSample) throws {
    let checker = try BundledSchemaLoader().loadChecker(for: sample.schema)

    let failures = try checker.check(authored(sample.json))

    #expect(failures.isEmpty == sample.isValid, "\(failures.map(\.description))")
  }
}
