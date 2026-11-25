import UseCasesCore

extension StatusReport {
  /// One line per use case, worst first, then the warnings, a blank line, the summary and the
  /// hint (chapter 16 §9).
  func listText(hint: Bool) -> String {
    let summary = StatusSummary(shown)
    var lines = listing(of: shown)

    lines += warningLines()
    lines += [
      "",
      Self.summaryLine(summary),
    ]
    lines += storeLines

    if hint, let line = listHint() {
      lines.append(line)
    }

    return lines.joined(separator: "\n")
  }

  /// The single line of a checkout where nothing has run yet (chapter 16 §9), then the warnings
  /// and the hint. It counts the READY use cases, with the drafts after them.
  func oneLineText(hint: Bool) -> String {
    let drafts = workspace.useCases.count { useCase in
      !useCase.isReady
    }
    let ready = workspace.useCases.count - drafts
    let draftNote = drafts == 0 ? "" : " (\(drafts) draft)"

    var lines = [
      "no verdicts in this checkout yet: \(Self.count(ready, "use case"))\(draftNote), "
        + "none run here",
    ]

    lines += warningLines()
    lines += storeLines

    if hint {
      lines.append(hintLine("\(verifyStep)   for a baseline, if you want one"))
    }

    return lines.joined(separator: "\n")
  }

  /// A line for each use case, with the reasons lined up. `marks` adds text at the end of a line,
  /// by use case id.
  func listing(
    of useCases: [UseCaseStatus],
    marks: [String: String] = [:],
  ) -> [String] {
    let fronts = useCases.map { useCase in
      "\(useCase.status.marked.padded(toWidth: 12))  \(useCase.identifier)"
    }
    let width = (fronts.map(\.count).max() ?? 0) + 2

    return zip(useCases, fronts).map { useCase, front in
      let reason = useCase.listingReason(shortening: workspace.runIdentifiers)
      let mark = marks[useCase.identifier]

      guard reason != nil || mark != nil else {
        return front
      }

      let text = [reason, mark].compactMap(\.self).joined(separator: "   ")

      return front.padded(toWidth: width) + text
    }
  }

  static func summaryLine(_ summary: StatusSummary) -> String {
    ([count(summary.total, "use case")] + summary.counts).joined(separator: " · ")
  }

  static func count(
    _ number: Int,
    _ noun: String,
  ) -> String {
    number == 1 ? "1 \(noun)" : "\(number) \(noun)s"
  }

  /// What a person most likely wants next (chapter 16 §18): the first use case that needs a look,
  /// else the step that gets verdicts.
  private func listHint() -> String? {
    let needsLook = shown.first { useCase in
      [.failed, .error, .incomplete].contains(useCase.status)
    }

    if let needsLook {
      return hintLine("status \(needsLook.identifier)   to see why")
    }

    let wantsVerdicts = shown.contains { useCase in
      [.stale, .unverified].contains(useCase.status)
    }

    if wantsVerdicts {
      return hintLine(verifyStep)
    }

    return pruneHint
  }

  /// The store's line, when it holds any run.
  private var storeLines: [String] {
    workspace.store.map { store in
      [store.line]
    } ?? []
  }

  /// `prune`, only when it would remove a run (chapter 16 §18).
  private var pruneHint: String? {
    guard let superseded = workspace.store?.superseded, superseded > 0 else {
      return nil
    }

    return hintLine("prune   to remove \(Self.count(superseded, "superseded run"))")
  }
}
