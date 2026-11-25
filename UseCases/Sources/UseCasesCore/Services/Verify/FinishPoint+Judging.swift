extension FinishPoint {
  static let codeChanged = "code changed during the run"
  static let notLinked = "not linked: no validation links and no procedure"
  static let didntRun = "its test didn't run"

  /// Judges every READY route of the workspace from the merged results (chapter 13 §7 step 5),
  /// then applies the guard (§8) to the verdicts: a route whose code is not the code the start
  /// point noted keeps no verdict.
  ///
  /// - Parameters:
  ///   - outcomes: What reading the sources gave.
  ///   - stamp: The start point.
  ///   - resolved: The workspace the results were asked for, with its links.
  ///   - guarded: The fingerprints of the workspace read again after the reports were read.
  func judged(
    _ outcomes: [SourceOutcome],
    stamp: StartStamp,
    resolved: ResolvedWorkspace,
    guarded: RouteFingerprints,
  ) -> Judged {
    let guardian = Guardian(
      stamp: stamp,
      guarded: guarded,
    )
    let keys = Self.validationLinkKeys(of: resolved.links)
    var order: [RouteKey] = []
    var judgeable: [JudgedRoute] = []

    for useCase in resolved.workspace.useCases where useCase.definition.authoredState == .ready {
      for route in useCase.definition.routes {
        let key = RouteKey(
          useCase: useCase.identifier,
          route: route.identifier,
        )

        order.append(key)
        judgeable.append(
          JudgedRoute(
            key: key,
            linkKeys: keys[key] ?? [],
            hasProcedure: route.procedure != nil,
          ),
        )
      }
    }

    return assemble(
      order: order,
      outcomes: judge.judge(
        judgeable,
        from: outcomes,
      ),
      guardian: guardian,
      links: resolved.links,
    )
  }

  private static func validationLinkKeys(of links: LinkResolution) -> [RouteKey: [String]] {
    var keys: [RouteKey: [String]] = [:]

    for link in links.links {
      guard let route = link.identity.route else {
        continue
      }

      keys[
        RouteKey(
          useCase: link.identity.useCase,
          route: route,
        ),
        default: [],
      ].append(link.key)
    }

    return keys
  }
}
