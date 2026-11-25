/// Shows a use case as the definition `save` takes, with its state and its sign-off.
public struct UseCaseShower: UseCaseShowing {
  private let fingerprinter: any PromiseFingerprinting
  private let serialiser: any UseCaseSerialising

  /// Makes the shower.
  public init() {
    self.init(
      fingerprinter: PromiseFingerprinter(),
      serialiser: UseCaseSerialiser(),
    )
  }

  init(
    fingerprinter: any PromiseFingerprinting,
    serialiser: any UseCaseSerialising,
  ) {
    self.fingerprinter = fingerprinter
    self.serialiser = serialiser
  }

  /// The use case with exactly this full id, compared by its UTF-8 bytes.
  public func show(
    _ identifier: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseShowingError) -> ShownUseCase {
    guard
      let useCase = workspace.useCases.first(where: { useCase in
        useCase.identifier.text.isExactlyEqual(to: identifier)
      })
    else {
      throw .unknown(identifier: identifier)
    }

    let definition = useCase.definition
    let state = definition.authoredState

    return try ShownUseCase(
      identifier: useCase.identifier.text,
      file: useCase.file.text,
      isReady: state == .ready,
      missing: missing(in: state),
      approval: approval(of: useCase),
      definition: definition.document(identifier: useCase.identifier),
      yamlLines: serialiser.lines(
        of: definition,
        writing: useCase.identifier.text,
      ),
    )
  }

  private func missing(in state: AuthoredState) -> [String] {
    guard case let .draft(gaps) = state else {
      return []
    }

    return gaps.map(\.words)
  }

  private func approval(of useCase: LoadedUseCase) throws(UseCaseShowingError) -> ApprovalState {
    let promise: String

    do {
      promise = try fingerprinter.fingerprint(
        of: PromiseFingerprintInput(
          definition: useCase.definition,
          identifier: useCase.identifier,
        ),
      )
    } catch {
      throw .unfingerprintable(
        identifier: useCase.identifier.text,
        reason: "\(error)",
      )
    }

    return ApprovalState(
      approval: useCase.definition.approval,
      promise: promise,
    )
  }
}
