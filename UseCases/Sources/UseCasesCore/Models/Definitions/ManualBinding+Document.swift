extension ManualBinding {
  /// The binding as it is authored under `bindings` (chapter 08).
  var document: StoreJSONValue {
    .members([
      "id": .string(identifier.text),
      "kind": .string("manual"),
      "locator": locator.document,
    ])
  }
}

private extension ManualLocator {
  var document: StoreJSONValue {
    .present([
      "file": .string(file.text),
      "start": range.map { range in
        range.start.document
      },
      "end": range.map { range in
        range.end.document
      },
    ])
  }
}

private extension SourcePosition {
  var document: StoreJSONValue {
    .present([
      "line": .integer(line),
      "column": column.map(StoreJSONValue.integer),
    ])
  }
}
