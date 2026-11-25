/// The guard of chapter 13 §8: a route's verdict is kept only if the code its fingerprint covers
/// is the code the start point noted.
struct Guardian {
  /// The fingerprint of every route at the start point.
  let started: [RouteKey: RouteFingerprint]

  private let startedFiles: [String: String]
  private let guardedFiles: [String: String]
  private let live: [String: LiveRouteFingerprint]

  init(
    stamp: StartStamp,
    guarded: RouteFingerprints,
  ) {
    var started: [RouteKey: RouteFingerprint] = [:]
    for route in stamp.routes where started[route.key] == nil {
      started[route.key] = route.fingerprint
    }

    var live: [String: LiveRouteFingerprint] = [:]
    for route in guarded.routes {
      live[Self.name(of: route.useCase, route.route)] = route
    }

    self.started = started
    self.live = live
    startedFiles = Self.byPath(stamp.files)
    guardedFiles = Self.byPath(guarded.fileDigests)
  }

  /// The reason a route the start point did not know has no verdict. It has no fingerprint to
  /// name, and nothing to say about files.
  func unknown(_ key: RouteKey) -> RunDiagnostic {
    RunDiagnostic(
      problem: FinishPoint.codeChanged,
      useCase: key.useCase,
      route: key.route,
      fingerprint: nil,
      files: [],
      links: [],
    )
  }

  /// The reason a route loses its verdict when its code is not the start point's, or `nil` when
  /// it is.
  func changed(_ key: RouteKey) -> RunDiagnostic? {
    guard let began = started[key] else {
      return unknown(key)
    }

    let now = live[Self.name(of: key.useCase.text, key.route.text)]

    guard now?.fingerprint != began.text else {
      return nil
    }

    return RunDiagnostic(
      problem: FinishPoint.codeChanged,
      useCase: key.useCase,
      route: key.route,
      fingerprint: began,
      files: moved(now?.files ?? []),
      links: [],
    )
  }

  /// The files of a route whose bytes are not what they were at the start point. A route that
  /// has no file now, because it lost its links, names every file of the start point that
  /// moved: the person sees what changed, not nothing.
  private func moved(_ files: [String]) -> [WorkspacePath] {
    let candidates = files.isEmpty ? startedFiles.keys.sorted() : files

    return candidates
      .filter { startedFiles[$0] != guardedFiles[$0] }
      .compactMap { file in
        try? WorkspacePath(validating: file)
      }
  }

  private static func byPath(_ digests: [FileDigest]) -> [String: String] {
    var found: [String: String] = [:]

    for digest in digests {
      found[digest.path] = digest.digest
    }

    return found
  }

  private static func name(
    of useCase: String,
    _ route: String,
  ) -> String {
    "\(useCase)#\(route)"
  }
}
