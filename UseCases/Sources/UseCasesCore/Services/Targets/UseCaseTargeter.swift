/// Reads targets against the use cases of a loaded workspace.
public struct UseCaseTargeter: UseCaseTargeting {
  /// Makes the targeter.
  public init() {}

  /// The full ids of the use cases `target` names: the exact id alone when there is one, and
  /// otherwise every id under it as a prefix. Ids compare by their UTF-8 bytes.
  public func identifiers(
    matching target: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseTargetingError) -> Set<String> {
    let known = workspace.useCases.map(\.identifier.text)

    let isExact = known.contains { identifier in
      identifier.isExactlyEqual(to: target)
    }

    if isExact {
      return [target]
    }

    let prefix = Array((target + ".").utf8)
    let under = known.filter { identifier in
      identifier.utf8.starts(with: prefix)
    }

    guard !under.isEmpty else {
      throw .unmatched(target: target)
    }

    return Set(under)
  }
}
