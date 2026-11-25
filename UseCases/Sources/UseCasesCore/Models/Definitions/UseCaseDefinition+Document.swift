extension UseCaseDefinition {
  /// The use case whole, as its fields are authored and with its full id: the shape `definition`
  /// names in the published CLI schemas, which is what a transformer is told each use case is
  /// (chapter 10 §11). A field that is empty, or a default, is left out.
  func document(identifier: UseCaseIdentifier) -> StoreJSONValue {
    document(writing: identifier.text)
  }

  /// The same, with `id` written as given: the full id, or the local one a definition file
  /// holds.
  func document(writing id: String) -> StoreJSONValue {
    .present([
      "id": .string(id),
      "title": .string(title),
      "description": description.map(StoreJSONValue.string),
      "value_tier": valueTier.map { tier in
        .string(tier.rawValue)
      },
      "intent": intent.map(StoreJSONValue.string),
      "out_of_scope": outOfScope.isEmpty ? nil : .strings(outOfScope),
      "scenarios": scenarios.isEmpty ? nil : .array(scenarios.map(\.document)),
      "validation": routes.isEmpty ? nil : .array(routes.map(\.document)),
      "bindings": bindings.isEmpty ? nil : .array(bindings.map(\.document)),
      "approved": approval.map(\.document),
    ])
  }
}

private extension Scenario {
  var document: StoreJSONValue {
    .present([
      "id": .string(identifier.text),
      "given": given.isEmpty ? nil : .strings(given),
      "when": when.isEmpty ? nil : .strings(when),
      "then": then.isEmpty ? nil : .strings(then),
    ])
  }
}

extension Approval {
  var document: StoreJSONValue {
    .members([
      "by": .string(approver),
      "on": .string(day),
      "behaviour": .string(behaviour),
    ])
  }
}
