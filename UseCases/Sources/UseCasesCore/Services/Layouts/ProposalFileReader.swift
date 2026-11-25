import Foundation

/// Reads a proposal file once: its own keys first, so that a key it does not know is named as a
/// proposal's, and then the batch inside it, held to what `apply` holds a batch to.
struct ProposalFileReader: ProposalFileReading {
  private static let keys = ["remove", "save"] + UseCaseBatchReader.proposalKeys

  private let reader: any AuthoredInputReading
  private let batches: any UseCaseBatchReading

  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  init(workingDirectory: URL) {
    self.init(
      reader: AuthoredInputReader(workingDirectory: workingDirectory),
      batches: UseCaseBatchReader(workingDirectory: workingDirectory),
    )
  }

  init(
    reader: any AuthoredInputReading,
    batches: any UseCaseBatchReading,
  ) {
    self.reader = reader
    self.batches = batches
  }

  func read(_ argument: String) throws(LayoutRenderingError) -> ProposalFile {
    let input: AuthoredInput

    do {
      input = try reader.read(AuthoredInputSource(argument: argument))
    } catch {
      throw .input(message: error.message)
    }

    guard let object = try? AuthoredObject(input.value, at: "") else {
      throw .batch(
        .notABatch(
          name: input.name,
          problem: nil,
        ),
      )
    }

    try requireKnownKeys(
      of: object,
      named: input.name,
    )

    let presentation = try ProposalPresentation(
      reading: object,
      named: input.name,
    )
    let batch = try batch(from: input)

    return ProposalFile(
      name: input.name,
      title: presentation.title,
      batch: batch,
      untouched: presentation.untouched,
      fits: presentation.fits,
      youSee: presentation.youSee,
      decisions: presentation.decisions,
      golden: presentation.golden,
    )
  }

  private func requireKnownKeys(
    of object: AuthoredObject,
    named name: String,
  ) throws(LayoutRenderingError) {
    let strangers = object.members.map(\.key).filter { key in
      !Self.keys.contains { known in
        known.isExactlyEqual(to: key)
      }
    }

    guard strangers.isEmpty else {
      throw .invalidProposal(
        name: name,
        problem: "a proposal has \(Self.keys.joined(separator: ", ")); "
          + "unknown: \(strangers.joined(separator: ", "))",
      )
    }
  }

  private func batch(from input: AuthoredInput) throws(LayoutRenderingError) -> UseCaseBatch {
    do {
      let batch = try batches.batch(from: input)
      try batch.requireEachOnce()

      return batch
    } catch {
      throw .batch(error)
    }
  }
}
