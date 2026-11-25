extension RunSource {
  /// The source as `run.json` writes it. A field the source does not have is left out.
  var document: StoreJSONValue {
    .present([
      "id": .string(identifier.text),
      "report": .string(report),
      "transformer": .string(transformer),
      "working_dir": workingDirectory.map(\.text).map(StoreJSONValue.string),
      "command": command.map(StoreJSONValue.strings),
      "exit_code": exitCode.map(StoreJSONValue.integer),
      "seconds": seconds.map(StoreJSONValue.number),
      "error": error.map(StoreJSONValue.string),
      "diagnostics": diagnostics.isEmpty ? nil : .strings(diagnostics),
    ])
  }
}
