/// The low-level helpers the planning modules share
/// (packages/core/src/presentation/planHelpers.ts): path normalisation and the
/// facts read off a row — steps, observations, verification requirements.
///
/// Rows are read as the JSON they are: a member of the wrong type is skipped
/// exactly where the TypeScript's `Array.isArray` / `typeof` guards skip it.
enum PresentationPlanHelpers {
  /// `resolvedSteps`: every scenario's `steps` when that is an array, else its
  /// `given`, `when` and `then` arrays, keeping only non-empty strings.
  static func resolvedSteps(_ useCase: LoadedUseCase) -> [String] {
    let steps = (useCase.value["scenarios"]?.arrayValue ?? []).flatMap { scenario -> [JSONValue] in
      if let steps = scenario["steps"]?.arrayValue {
        return steps
      }
      let given = scenario["given"]?.arrayValue ?? []
      let when = scenario["when"]?.arrayValue ?? []
      let then = scenario["then"]?.arrayValue ?? []
      return given + when + then
    }
    return nonEmptyStrings(steps)
  }

  /// `expectedObservations`: scenario outcomes, then the row's own, as
  /// non-empty strings with repeats dropped — identical by code unit, as a
  /// JavaScript `Set` compares them.
  static func expectedObservations(_ useCase: LoadedUseCase) -> [String] {
    let scenarioOutcomes = (useCase.value["scenarios"]?.arrayValue ?? []).flatMap { scenario in
      scenario["observable_outcomes"]?.arrayValue ?? []
    }
    let useCaseOutcomes = useCase.value["observable_outcomes"]?.arrayValue ?? []
    return uniqueStrings(nonEmptyStrings(scenarioOutcomes + useCaseOutcomes))
  }

  /// One well-formed verification requirement.
  struct VerificationRequirement {
    let evidenceKind: String
    let requiredVerifiers: [String]
    let minimumCount: Double
  }

  /// `verificationRequirements`: the policy's well-formed requirements, when
  /// its mode is `requirements` and it carries a list.
  static func verificationRequirements(_ useCase: LoadedUseCase) -> [VerificationRequirement] {
    let policy = policySnapshot(useCase.value["verification_policy"])
    guard policy["mode"]?.stringValue == "requirements",
          let requirements = policy["requirements"]?.arrayValue
    else {
      return []
    }
    return requirements.compactMap { requirement in
      guard let kind = requirement["evidence_kind"]?.stringValue,
            let verifiers = requirement["required_verifiers"]?.arrayValue,
            let minimumCount = requirement["minimum_count"]?.numberValue
      else {
        return nil
      }
      let names = verifiers.compactMap(\.stringValue)
      guard names.count == verifiers.count else {
        return nil
      }
      return VerificationRequirement(
        evidenceKind: kind,
        requiredVerifiers: names,
        minimumCount: minimumCount,
      )
    }
  }

  /// `normalizePaths`: each path normalised, then a bare `.sort()` — UTF-16
  /// code-unit order, duplicates kept.
  static func normalizedPaths(_ paths: [String]) -> [String] {
    paths.map(normalizedPath).sorted(by: JavaScriptStringOrder.codeUnitAscending)
  }

  /// `normalizePath`: backslashes become slashes, then one leading `./` goes.
  static func normalizedPath(_ path: String) -> String {
    var scalars = String.UnicodeScalarView(path.unicodeScalars.map { scalar in
      scalar == "\\" ? "/" : scalar
    })
    if scalars.starts(with: "./".unicodeScalars) {
      scalars.removeFirst(2)
    }
    return String(scalars)
  }

  /// `uniqueStrings`: first occurrences, in order, identical by code unit.
  static func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<CodeUnitKey>()
    return values.filter { value in
      seen.insert(CodeUnitKey(value)).inserted
    }
  }

  /// `policySnapshot`: an object as it is, anything else `{ mode: "none" }`.
  static func policySnapshot(_ value: JSONValue?) -> JSONObject {
    value?.objectValue ?? JSONObject([("mode", .string("none"))])
  }

  /// JavaScript `===` between two strings: the same code units.
  static func sameCodeUnits(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.utf16.elementsEqual(right.utf16)
  }

  private static func nonEmptyStrings(_ values: [JSONValue]) -> [String] {
    values.compactMap { value in
      guard let text = value.stringValue, !text.isEmpty else {
        return nil
      }
      return text
    }
  }
}
