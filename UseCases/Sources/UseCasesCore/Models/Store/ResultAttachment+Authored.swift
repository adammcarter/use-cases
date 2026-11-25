extension ResultAttachment {
  /// Reads a descriptor, after it passed the result schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let blob = try object.requiredString("blob")

    guard blob.hasPrefix(Self.blobPrefix) else {
      throw .invalidValue(
        location: object.location(of: "blob"),
        reason: "\(AuthoredValue.quote(blob)) is not a blob id",
      )
    }

    try self.init(
      name: object.requiredString("name"),
      digest: String(blob.dropFirst(Self.blobPrefix.count)),
      sizeBytes: object.requiredCount("size_bytes"),
      mediaType: object.optionalString("media_type"),
    )
  }
}
