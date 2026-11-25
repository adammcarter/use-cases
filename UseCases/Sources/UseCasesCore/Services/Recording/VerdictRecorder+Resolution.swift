extension VerdictRecorder {
  /// The use case a request names: the exact id, or else the one id that starts with the text.
  func useCase(
    named target: String,
    in workspace: LoadedWorkspace,
  ) throws(RecordingError) -> LoadedUseCase {
    let match = Self.match(
      target,
      among: workspace.useCases,
      by: { $0.identifier.text },
    )

    switch match {
    case let .found(useCase):
      return useCase
    case .none:
      throw .noUseCase(target)
    case let .several(ids):
      throw .ambiguousUseCase(
        target,
        matching: ids,
      )
    }
  }

  /// The route a request names: the exact id, or else the one route id that starts with the text.
  /// The route is looked for before the use case is judged, so a route that is not there is
  /// reported for a DRAFT as well.
  func route(
    named target: String,
    of useCase: LoadedUseCase,
  ) throws(RecordingError) -> ValidationRoute {
    let match = Self.match(
      target,
      among: useCase.definition.routes,
      by: { $0.identifier.text },
    )

    switch match {
    case let .found(route):
      return route
    case .none:
      throw .noRoute(
        useCase: useCase.identifier.text,
        route: target,
      )
    case let .several(ids):
      throw .ambiguousRoute(
        useCase: useCase.identifier.text,
        route: target,
        matching: ids,
      )
    }
  }
}
