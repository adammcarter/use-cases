/// Places a new use case in the file that holds its group, or in a new file at the structured
/// path.
struct UseCasePlacer: UseCasePlacing {
  func place(
    _ identifier: UseCaseIdentifier,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCasePlacement {
    let segments = identifier.namespace.segments

    guard segments.count > 1 else {
      throw .noGroup(identifier: identifier.text)
    }

    let group = Array(segments.dropLast())
    let namespaces = workspace.scopeNamespaces

    if let file = holder(
      of: group,
      in: workspace,
      namespaces: namespaces,
    ) {
      return .existing(file: file)
    }

    if let flat = namespaces.first(where: { $0.segments == group }) {
      throw .needsGroup(
        identifier: identifier.text,
        namespace: flat.text,
      )
    }

    var owner: ScopeNamespace?

    for candidate in namespaces
      where candidate.segments.count < group.count
      && Array(group.prefix(candidate.segments.count)) == candidate.segments
      && candidate.segments.count > (owner?.segments.count ?? -1)
    {
      owner = candidate
    }

    guard let owner else {
      throw .outsideNamespaces(
        identifier: identifier.text,
        namespace: namespaces.first?.text ?? "",
      )
    }

    return newFile(
      for: Array(group.dropFirst(owner.segments.count)),
      in: owner,
    )
  }

  /// The first file by path whose use cases are all in the group: a file with a prefix of its
  /// own, composed after its scope's.
  private func holder(
    of group: [IdentifierSegment],
    in workspace: LoadedWorkspace,
    namespaces: [ScopeNamespace],
  ) -> WorkspacePath? {
    let prefixed = Dictionary(
      uniqueKeysWithValues: namespaces.map { namespace in
        (namespace.scope.discovered.directory, namespace.segments.count < group.count)
      },
    )

    return workspace.useCases.filter { useCase in
      Array(useCase.identifier.namespace.segments.dropLast()) == group
        && prefixed[useCase.scope] == true
    }.map(\.file).min()
  }

  private func newFile(
    for prefix: [IdentifierSegment],
    in owner: ScopeNamespace,
  ) -> UseCasePlacement {
    var file = owner.scope.discovered.useCasesDirectory

    for segment in prefix.dropLast() {
      file = file.appending(literal: segment.text)
    }

    file = file.appending(literal: (prefix.last?.text ?? "") + ".yml")

    let joined = prefix.dropFirst().reduce(Namespace(prefix[0])) { namespace, segment in
      namespace.appending(Namespace(segment))
    }

    return .new(
      file: file,
      prefix: joined,
    )
  }
}
