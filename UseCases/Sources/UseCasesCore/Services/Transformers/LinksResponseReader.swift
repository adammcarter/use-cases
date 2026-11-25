/// Reads the `links` and `diagnostics` of a links response, typing every member the core knows.
struct LinksResponseReader: LinksResponseReading {
  func read(
    _ response: AuthoredObject,
    from name: String,
  ) throws(TransformerError) -> LinksAnswer {
    do {
      guard response.contains("links") else {
        throw AuthoredShapeError.missing(location: "links")
      }

      return try LinksAnswer(
        links: response.objects("links").map(link(in:)),
        diagnostics: response.contains("diagnostics") ? response.strings("diagnostics") : nil,
      )
    } catch {
      throw .malformedResponse(
        name: name,
        reason: "\(error)",
      )
    }
  }

  private func link(in object: AuthoredObject) throws(AuthoredShapeError) -> TransformerLink {
    try TransformerLink(
      useCase: object.optionalString("use_case"),
      route: object.optionalString("route"),
      binding: object.optionalString("binding"),
      role: object.optionalString("role"),
      file: object.optionalString("file"),
      range: range(in: object),
      text: StoreJSONWriter().compact(
        StoreJSONValue(.object(object.members)),
      ).lossyUTF8Text,
    )
  }

  private func range(
    in object: AuthoredObject,
  ) throws(AuthoredShapeError) -> TransformerLinkRange? {
    guard let range = try object.optionalObject("range") else {
      return nil
    }

    return try TransformerLinkRange(
      start: range.contains("start") ? range.requiredInteger("start") : nil,
      end: range.contains("end") ? range.requiredInteger("end") : nil,
    )
  }
}
