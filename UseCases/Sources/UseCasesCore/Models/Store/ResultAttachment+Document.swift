extension ResultAttachment {
  /// The descriptor as a result writes it (chapter 12 §16).
  var document: StoreJSONValue {
    .present([
      "name": .string(name),
      "blob": .string(blob),
      "size_bytes": .integer(sizeBytes),
      "media_type": mediaType.map(StoreJSONValue.string),
    ])
  }
}
