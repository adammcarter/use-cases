import UseCasesCore

extension StatusCommand {
  /// The answer to a request that was understood and judged.
  func report(
    of status: WorkspaceStatus,
    named: Set<String>?,
    members: Set<String>?,
    filter: StatusStateFilter?,
  ) -> CommandResult {
    // The target, the group and the states all have to hold (chapter 16 §9).
    let shown = status.useCases.filter { useCase in
      (named?.contains(useCase.identifier) ?? true)
        && (members?.contains(useCase.identifier) ?? true)
        && (filter?.contains(useCase.status) ?? true)
    }

    let report = StatusReport(
      workspace: status,
      shown: shown,
      group: group,
      offersRun: status.hasRunCommand,
    )

    if gate {
      // A group is gated on its members only (chapter 16 §10).
      let scope = members.map(status.limited(to:)) ?? status

      return gateResult(
        scope.gate(strict: strict),
        report: report,
      )
    }

    guard !global.json else {
      return jsonResult(
        report,
        gate: nil,
      )
    }

    return .done(
      humanText(
        of: report,
        isDetail: named?.count == 1 && named?.first == target,
      ),
    )
  }

  private func gateResult(
    _ gate: Gate,
    report: StatusReport,
  ) -> CommandResult {
    let answer =
      global.json
        ? jsonResult(
          report,
          gate: gate,
        )
        : CommandResult.done(
          report.gateText(
            gate,
            hint: !global.quiet,
          ),
        )

    guard !gate.passed else {
      return answer
    }

    return .needsAttention(answer.standardOutput)
  }

  private func jsonResult(
    _ report: StatusReport,
    gate: Gate?,
  ) -> CommandResult {
    do {
      return try .done(report.jsonText(gate: gate))
    } catch {
      return .refusal(
        .refused,
        message: "the status could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }

  private func humanText(
    of report: StatusReport,
    isDetail: Bool,
  ) -> String {
    let hint = !global.quiet

    if isDetail, let useCase = report.shown.first {
      return report.detailText(
        of: useCase,
        hint: hint,
      )
    }

    let isUnrun = target == nil && group == nil && state == nil
      && !report.workspace.hasSealedRuns
    let hasReady = report.workspace.useCases.contains(where: \.isReady)

    guard isUnrun, hasReady else {
      return report.listText(hint: hint)
    }

    return report.oneLineText(hint: hint)
  }
}
