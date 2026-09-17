/// Binding runbook steps to the plan, and resolving command working
/// directories.
extension DemoCapsuleRunner {
  /// `plannedCapsuleSteps`: every runbook step of every item, bound to the
  /// plan item selected for its use case, or a diagnostic for each item the
  /// plan did not select.
  static func plannedSteps(
    _ capsule: DemoCapsule,
    plan: PresentationPlan,
  ) -> Result<[DemoCapsulePlannedStep], DemoCapsuleBlockingDiagnostics> {
    var planItems: [CodeUnitKey: String] = [:]
    for item in plan.selectedItems {
      planItems[CodeUnitKey(item.useCaseIdentifier)] = item.planItemIdentifier
    }
    var steps: [DemoCapsulePlannedStep] = []
    var diagnostics: [Diagnostic] = []
    for (itemIndex, item) in capsule.items.enumerated() {
      guard let planItemIdentifier = planItems[CodeUnitKey(item.useCaseIdentifier)] else {
        diagnostics.append(Diagnostic(
          code: "capsule.plan_item_missing",
          message: "Capsule use case '\(item.useCaseIdentifier)' was not selected in the "
            + "generated plan.",
          entityIdentifier: item.useCaseIdentifier,
        ))
        continue
      }
      for (stepIndex, step) in item.runbook.enumerated() {
        steps.append(DemoCapsulePlannedStep(
          itemIndex: itemIndex,
          stepIndex: stepIndex,
          useCaseIdentifier: item.useCaseIdentifier,
          planItemIdentifier: planItemIdentifier,
          step: step,
        ))
      }
    }
    return diagnostics.isEmpty ? .success(steps) : .failure(DemoCapsuleBlockingDiagnostics(
      diagnostics: diagnostics,
    ))
  }

  /// `resolveCommandSteps`: each command's working directory resolved against
  /// the workspace and, when it exists, through its symlinks; a diagnostic for
  /// each one that lands outside the workspace's real path.
  static func workingDirectories(
    _ commandSteps: [DemoCapsulePlannedStep],
    context: ResolvedWorkspaceContext,
  ) throws(DemoCapsuleError) -> Result<[String], DemoCapsuleBlockingDiagnostics> {
    let workspaceRealPath: String
    do throws(FileAccessError) {
      workspaceRealPath = try NodeFile.realPath(context.workspaceRoot)
    } catch {
      throw .fileAccess(error)
    }
    var directories: [String] = []
    var diagnostics: [Diagnostic] = []
    for entry in commandSteps {
      let requested = entry.command?.workingDirectory ?? ""
      let candidate = resolved(
        NodePath.isAbsolute(requested)
          ? requested
          : NodePath.join(context.workspaceRoot, requested.isEmpty ? "." : requested),
      )
      let checked = existingRealPath(candidate) ?? candidate
      let relativePath = NodePath.relative(from: workspaceRealPath, to: checked)
      if relativePath.utf16.starts(with: [CodeUnits.fullStop, CodeUnits.fullStop])
        || NodePath.isAbsolute(relativePath)
      {
        diagnostics.append(Diagnostic(
          code: "capsule.command_cwd_escape",
          message: "Command working_directory must stay inside repo.",
          entityIdentifier: entry.useCaseIdentifier,
        ))
      }
      directories.append(checked)
    }
    return diagnostics.isEmpty ? .success(directories) : .failure(DemoCapsuleBlockingDiagnostics(
      diagnostics: diagnostics,
    ))
  }

  /// `path.resolve` of an absolute path: normalized, no trailing separator.
  private static func resolved(_ path: String) -> String {
    var units = Array(NodePath.normalize(path).utf16)
    while units.count > 1, units.last == CodeUnits.solidus {
      units.removeLast()
    }
    return CodeUnits.string(units)
  }

  /// `existsSync(path) ? realpathSync(path) : nil`. A path holding a NUL does
  /// not exist to node.
  private static func existingRealPath(_ path: String) -> String? {
    guard !path.utf16.contains(0), NodeFile.exists(atPath: path) else {
      return nil
    }
    return try? NodeFile.realPath(path)
  }
}
