public extension VerdictRecorder {
  func offers(in workspace: LoadedWorkspace) -> [RecordOffer] {
    workspace.useCases.compactMap { useCase in
      guard case .ready = useCase.definition.authoredState else {
        return nil
      }

      return RecordOffer(
        useCase: useCase.identifier.text,
        routes: useCase.definition.routes.map { route in
          RecordRouteOffer(
            route: route.identifier.text,
            steps: route.procedure?.steps ?? [],
          )
        },
      )
    }
  }
}
