import Testing
@testable import UseCasesCore

/// The workspace of the batch tests, and the proposal files a test sends to the layouts:
/// `app.dark.toggle` (core, with the
/// intent "Readable at night.", the scenario `on-state` and the acceptance route `manual`),
/// `app.dark.other`, `app.solo.only` and `app.pay.card.charge`.
struct LayoutFixture {
  let batch: BatchFixture

  init() throws {
    batch = try BatchFixture()
  }

  /// A reader that finds the proposal the JSON text holds, whatever `--file` names.
  func reader(sending json: String) throws -> ProposalFileReader {
    let input = try MockAuthoredInput(AuthoredInput(name: "stdin", value: authored(json)))

    return ProposalFileReader(
      reader: input,
      batches: UseCaseBatchReader(
        reader: input,
        checker: UseCaseInputChecker(),
      ),
    )
  }

  func proposal(_ json: String) throws -> ProposalFile {
    try reader(sending: json).read("-")
  }

  /// The proposal drawn as a brief and as a proposal, which refuse it alike or not at all.
  func drawn(_ json: String) throws -> (brief: BriefLayout, proposal: ProposalLayout) {
    try (brief(json), proposalLayout(json))
  }

  func changes(_ json: String) throws -> [ResolvedChange] {
    try ProposalChangeResolver().changes(
      of: proposal(json),
      in: batch.loaded(),
    )
  }

  func brief(_ json: String) throws -> BriefLayout {
    try BriefRenderer(
      reader: reader(sending: json),
      resolver: ProposalChangeResolver(),
      checker: ProposalBatchChecker(),
    ).brief(
      readingFrom: "-",
      in: batch.loaded(),
    )
  }

  func proposalLayout(_ json: String) throws -> ProposalLayout {
    try ProposalRenderer(
      reader: reader(sending: json),
      resolver: ProposalChangeResolver(),
      checker: ProposalBatchChecker(),
    ).proposal(
      readingFrom: "-",
      in: batch.loaded(),
    )
  }

  func results(
    _ json: String,
    judging status: WorkspaceStatus,
  ) throws -> ResultsLayout {
    let loaded = try batch.loaded()

    return try ResultsRenderer(
      reader: reader(sending: json),
      resolver: ProposalChangeResolver(),
      judge: MockStatusJudging(status),
      fingerprinter: PromiseFingerprinter(),
    ).results(
      readingFrom: "-",
      in: loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )
  }

  /// What the layout refuses the proposal with.
  func refusal(_ json: String) throws -> LayoutRenderingError? {
    do {
      _ = try changes(json)

      return nil
    } catch let error as LayoutRenderingError {
      return error
    }
  }
}
