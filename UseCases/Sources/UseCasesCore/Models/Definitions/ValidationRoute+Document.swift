extension ValidationRoute {
  /// The route as it is authored (chapter 06). `gates_verification` is written only when it is
  /// not the default.
  var document: StoreJSONValue {
    .present([
      "id": .string(identifier.text),
      "type": type.document,
      "covers": .strings(covers.map(\.text)),
      "gates_verification": gatesVerification == Self.defaultGatesVerification
        ? nil
        : .boolean(gatesVerification),
      "procedure": procedure.map(\.document),
      "bindings": bindings.isEmpty ? nil : .array(bindings.map(\.document)),
      "resources": resources.isEmpty ? nil : .array(resources.map(\.document)),
    ])
  }
}

private extension ValidationType {
  var document: StoreJSONValue {
    switch self {
    case let .custom(name):
      .members([
        "kind": .string(kindName),
        "name": .string(name.text),
      ])
    default:
      .members(["kind": .string(kindName)])
    }
  }
}

private extension Procedure {
  var document: StoreJSONValue {
    .present([
      "setup": setup.isEmpty ? nil : .strings(setup),
      "steps": .strings(steps),
      "reset": reset.isEmpty ? nil : .strings(reset),
    ])
  }
}

private extension RouteResource {
  var document: StoreJSONValue {
    switch self {
    case let .file(path):
      .members([
        "kind": .string("file"),
        "path": .string(path.text),
      ])
    case let .glob(pattern):
      .members([
        "kind": .string("glob"),
        "pattern": .string(pattern.text),
      ])
    }
  }
}
