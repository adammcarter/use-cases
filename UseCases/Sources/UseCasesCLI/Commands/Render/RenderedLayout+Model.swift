import UseCasesCore

extension RenderedLayout {
  /// The `model` of the document, as `cli-render.schema.json` has it.
  var model: StoreJSONValue {
    switch self {
    case let .intent(layout):
      layout.model
    case let .brief(layout):
      layout.model
    case let .proposal(layout):
      layout.model
    case let .results(layout):
      layout.model
    }
  }
}

private extension IntentLayout {
  var model: StoreJSONValue {
    .members([
      "what": .string(what),
      "why": .string(why),
      "who": .strings(who),
    ])
  }
}

private extension BriefLayout {
  var model: StoreJSONValue {
    .members([
      "cards": .array(
        cards.map { card in
          card.model
        },
      ),
    ])
  }
}

private extension BriefCard {
  var model: StoreJSONValue {
    .present([
      "use_case": .string(useCase),
      "fit": .string(fit.rawValue),
      "title": .string(title),
      "tier": tier.map(StoreJSONValue.string),
      "now": .string(now),
      "was": was.map(StoreJSONValue.string),
      "scenarios": .array(
        scenarios.map { scenario in
          .members([
            "golden": .boolean(scenario.isGolden),
            "text": .string(scenario.text),
          ])
        },
      ),
      "not_included": .strings(notIncluded),
      "proven_by": .strings(provenBy),
    ])
  }
}

private extension ProposalLayout {
  var model: StoreJSONValue {
    .members([
      "title": .string(title),
      "changes": .array(
        changes.map { change in
          .present([
            "use_case": .string(change.useCase),
            "fit": .string(change.fit.rawValue),
            "title": .string(change.title),
            "tier": change.tier.map(StoreJSONValue.string),
            "you_see": change.youSee.map(StoreJSONValue.string),
          ])
        },
      ),
      "decisions": .array(
        decisions.map { decision in
          .members([
            "question": .string(decision.question),
            "options": .strings(decision.options),
          ])
        },
      ),
      "sign_off": signOff.model,
    ])
  }
}

private extension SignOffCounts {
  /// The tiers that have use cases to sign, and no others.
  var model: StoreJSONValue {
    .present([
      "critical": critical > 0 ? .integer(critical) : nil,
      "core": core > 0 ? .integer(core) : nil,
      "supporting": supporting > 0 ? .integer(supporting) : nil,
      "no_tier": untiered > 0 ? .integer(untiered) : nil,
    ])
  }
}

private extension ResultsLayout {
  var model: StoreJSONValue {
    .members([
      "title": .string(title),
      "use_cases": .array(
        useCases.map { useCase in
          .members([
            "use_case": .string(useCase.useCase),
            "title": .string(useCase.title),
            "status": .string(useCase.status.rawValue),
            "checks": .array(
              useCase.checks.map { check in
                .members([
                  "label": .string(check.label),
                  "status": .string(check.status.rawValue),
                ])
              },
            ),
          ])
        },
      ),
      "removed": .strings(removed),
      "gate": .boolean(gatePasses),
    ])
  }
}
