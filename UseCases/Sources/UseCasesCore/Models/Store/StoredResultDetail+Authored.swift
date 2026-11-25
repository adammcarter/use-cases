extension StoredResultDetail {
  /// Reads the members of a version 1 record beyond its envelope.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var attachments: [ResultAttachment] = []
    for attachment in try object.objects("attachments") {
      try attachments.append(ResultAttachment(authored: attachment))
    }

    try self.init(
      recordedAt: object.requiredString("recorded_at"),
      origin: ResultOrigin(authored: object),
      message: object.optionalString("message"),
      attachments: attachments,
    )
  }
}
