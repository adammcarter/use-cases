extension StatusJudge {
  /// What is worth saying about the workspace as a whole: the load's and the links' warnings that
  /// no use case owns, the resource warnings, each run that never finished and the damage found
  /// beside the verdicts of sealed runs (chapter 12 §15, §22).
  func warnings(using inputs: StatusInputs) -> [WorkspaceWarning] {
    let owned = Set(inputs.emptyRegions.map(\.diagnostic))

    var warnings = (inputs.links.warnings + inputs.workspace.rootFileWarnings).inReportOrder
      .filter { warning in
        !owned.contains(warning)
      }
      .map { warning in
        WorkspaceWarning.note(warning.description)
      }

    warnings += inputs.fingerprints.warningLines.map(WorkspaceWarning.note)
    warnings += inputs.history.unfinishedRuns.map { run in
      WorkspaceWarning.runNeverFinished(run: run.identifier.text)
    }
    warnings += inputs.history.findings.map { finding in
      WorkspaceWarning.note(finding.description)
    }

    return warnings
  }
}
