/// A use case the proposal saved, and where it stands (chapter 21 §7, step 8).
public struct ResultUseCase: Equatable, Sendable {
  /// The full id.
  public let useCase: String

  public let title: String

  /// Its status as `status` judges it now.
  public let status: VerificationStatus

  /// The routes that gate it; empty for a draft.
  public let checks: [ResultCheck]

  /// A use case of the results.
  public init(
    useCase: String,
    title: String,
    status: VerificationStatus,
    checks: [ResultCheck],
  ) {
    self.useCase = useCase
    self.title = title
    self.status = status
    self.checks = checks
  }
}

extension ResultUseCase {
  /// A use case as `status` judges it: its status, and the routes that gate it.
  init(_ status: UseCaseStatus) {
    self.init(
      useCase: status.identifier,
      title: status.title,
      status: status.status,
      checks: status.routes.filter(\.gates).map { route in
        ResultCheck(
          label: route.identifier,
          status: route.status,
        )
      },
    )
  }
}
