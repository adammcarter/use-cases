/// The use cases a link may name, by their full ids (chapter 08).
struct LinkTargets: Sendable {
  private let useCases: [UseCaseIdentifier: LoadedUseCase]

  init(_ useCases: [LoadedUseCase]) {
    self.useCases = Dictionary(
      useCases.map { useCase in
        (useCase.identifier, useCase)
      },
      uniquingKeysWith: { first, _ in
        first
      },
    )
  }

  /// The use case with this id; `nil` when the text is no id or names no use case.
  func useCase(named text: String) -> LoadedUseCase? {
    guard let identifier = try? UseCaseIdentifier(validating: text) else {
      return nil
    }

    return useCases[identifier]
  }
}
