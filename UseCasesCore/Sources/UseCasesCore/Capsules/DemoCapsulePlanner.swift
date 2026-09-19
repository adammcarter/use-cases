/// Plans a capsule's presentation (`planDemoCapsule`).
public enum DemoCapsulePlanner {
  /// Every capsule plan is generated and evaluated at this fixed instant.
  static let planInstant = "2026-06-25T12:00:00.000Z"

  /// `planDemoCapsule`: blocked while any capsule file is broken, even when
  /// the one asked for loaded; otherwise the capsule's own audience, timebox
  /// and use cases planned in its mode.
  public static func plan(
    context: ResolvedWorkspaceContext,
    capsuleIdentifier: String,
    registry: SchemaRegistry,
  ) throws(DemoCapsuleError) -> CapsulePlanResult {
    let snapshot = try DemoCapsuleLoader.load(context: context, registry: registry)
    let capsule = snapshot.capsules.first { loaded in
      JavaScriptString.identical(loaded.definition.capsuleIdentifier, capsuleIdentifier)
    }
    guard snapshot.isComplete else {
      return CapsulePlanResult(
        outcome: .integrityBlocked,
        capsule: capsule,
        planResult: nil,
        diagnostics: snapshot.diagnostics,
      )
    }
    guard let capsule else {
      return CapsulePlanResult(
        outcome: .capsuleNotFound,
        capsule: nil,
        planResult: nil,
        diagnostics: [Diagnostic(
          code: "capsule.not_found",
          message: "Capsule '\(capsuleIdentifier)' was not found.",
          entityIdentifier: capsuleIdentifier,
        )],
      )
    }

    let inputs = try planInputs(context: context, registry: registry)
    let definition = capsule.definition
    let planResult: PresentationPlanResult
    do throws(PresentationError) {
      planResult = try PresentationPlanner.selectPlan(
        context: context,
        matrix: inputs.matrix,
        evidence: inputs.evidence,
        request: request(for: definition),
        profile: definition.mode == .showcase ? .showcase : .walkthrough,
      )
    } catch {
      throw .presentation(error)
    }

    return CapsulePlanResult(
      outcome: .generated,
      capsule: capsule,
      planResult: planResult,
      diagnostics: snapshot.diagnostics + inputs.matrix.diagnostics + inputs.evidence.diagnostics,
    )
  }

  /// The capsule's own audience, timebox and use cases, at the fixed instant.
  private static func request(for definition: DemoCapsule) -> PresentationPlanRequest {
    PresentationPlanRequest(
      audience: definition.audience,
      timeboxSeconds: definition.timeboxSeconds,
      maxItems: Double(definition.items.count),
      requestedUseCaseIdentifiers: definition.items.map(\.useCaseIdentifier),
      generatedAt: planInstant,
      freshnessEvaluatedAt: planInstant,
    )
  }

  /// The matrix, then the evidence, as planning reads them.
  private static func planInputs(
    context: ResolvedWorkspaceContext,
    registry: SchemaRegistry,
  ) throws(DemoCapsuleError) -> (matrix: MatrixSnapshot, evidence: EvidenceSnapshot) {
    let matrix: MatrixSnapshot
    do throws(UseCaseMatrixError) {
      matrix = try UseCaseMatrixLoader.load(context: context, registry: registry)
    } catch {
      throw .matrix(error)
    }
    do throws(EvidenceEventError) {
      return try (matrix, EvidenceReplay.replay(context: context))
    } catch {
      throw .evidence(error)
    }
  }
}
