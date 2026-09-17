/// A filter over a snapshot's addressable rows. An empty list places no
/// constraint, exactly as an absent one does in the TypeScript.
///
/// Values are plain strings, not enums: a caller asking for a value tier that
/// does not exist gets no rows, which is what the TypeScript's `includes` gives.
public struct UseCaseQuery: Sendable, Equatable {
  public var valueTiers: [String]
  public var journeyRoles: [String]
  public var lifecycles: [String]
  public var hostSurfaces: [String]
  public var tagsAny: [String]
  public var tagsAll: [String]
  public var changedPaths: [String]

  public init(
    valueTiers: [String] = [],
    journeyRoles: [String] = [],
    lifecycles: [String] = [],
    hostSurfaces: [String] = [],
    tagsAny: [String] = [],
    tagsAll: [String] = [],
    changedPaths: [String] = [],
  ) {
    self.valueTiers = valueTiers
    self.journeyRoles = journeyRoles
    self.lifecycles = lifecycles
    self.hostSurfaces = hostSurfaces
    self.tagsAny = tagsAny
    self.tagsAll = tagsAll
    self.changedPaths = changedPaths
  }
}

extension MatrixSnapshot {
  /// `queryUseCases(snapshot, query)`: the addressable rows the query admits,
  /// by id in `localeCompare` order.
  public func queryUseCases(_ query: UseCaseQuery = UseCaseQuery()) -> [LoadedUseCase] {
    addressableUseCases
      .filter { item in
        Self.includes(query.valueTiers, item.value["value_tier"])
          && Self.includes(query.journeyRoles, item.value["journey_role"])
          && Self.includes(query.lifecycles, item.value["lifecycle"])
          && Self.matchesHostSurface(item, query)
          && Self.matchesTags(item, query)
          && Self.matchesChangedPaths(item, query)
      }
      .sorted { left, right in
        JavaScriptStringOrder.localeAscending(left.identifier, right.identifier)
      }
  }

  private static func includes(
    _ allowed: [String],
    _ value: JSONValue?,
  ) -> Bool {
    allowed.isEmpty || codeUnitSet(allowed).contains(key(value))
  }

  private static func matchesHostSurface(
    _ item: LoadedUseCase,
    _ query: UseCaseQuery,
  ) -> Bool {
    guard !query.hostSurfaces.isEmpty else {
      return true
    }
    let hosts = item.value["host_applicability"]?.arrayValue ?? []
    guard !hosts.isEmpty else {
      return true
    }
    let wanted = codeUnitSet(query.hostSurfaces)
    return hosts.contains { host in
      host["supported"] == .bool(true) && wanted.contains(key(host["host_surface"]))
    }
  }

  private static func matchesTags(
    _ item: LoadedUseCase,
    _ query: UseCaseQuery,
  ) -> Bool {
    let tags = Set((item.value["tags"]?.arrayValue ?? []).map(key))
    func hasTag(_ tag: String) -> Bool {
      tags.contains(CodeUnitKey(tag))
    }
    let anyMatches = query.tagsAny.isEmpty || query.tagsAny.contains(where: hasTag)
    let allMatch = query.tagsAll.isEmpty || query.tagsAll.allSatisfy(hasTag)
    return anyMatches && allMatch
  }

  private static func matchesChangedPaths(
    _ item: LoadedUseCase,
    _ query: UseCaseQuery,
  ) -> Bool {
    guard !query.changedPaths.isEmpty else {
      return true
    }
    let changed = Set(query.changedPaths.map { path in
      CodeUnitKey(normalizedPath(path))
    })
    return (item.value["source_refs"]?.arrayValue ?? []).contains { reference in
      guard reference["kind"] == .string("file"), let path = reference["path"]?.stringValue else {
        return false
      }
      return changed.contains(CodeUnitKey(normalizedPath(path)))
    }
  }

  /// `path.replaceAll("\\", "/").replace(/^\.\//, "")`, scalar by scalar so a
  /// backslash carrying a combining mark is still replaced.
  private static func normalizedPath(_ path: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in path.unicodeScalars {
      scalars.append(scalar == "\\" ? "/" : scalar)
    }
    let replaced = String(scalars)
    guard replaced.utf16.starts(with: [CodeUnits.fullStop, CodeUnits.solidus]) else {
      return replaced
    }
    return CodeUnits.string(replaced.utf16.dropFirst(2))
  }

  /// A JSON value as a code-unit key; anything but a string matches nothing a
  /// query can ask for.
  private static func key(_ value: JSONValue?) -> CodeUnitKey? {
    value?.stringValue.map(CodeUnitKey.init)
  }

  private static func codeUnitSet(_ strings: [String]) -> Set<CodeUnitKey?> {
    Set(strings.map { string in
      CodeUnitKey(string)
    })
  }
}
