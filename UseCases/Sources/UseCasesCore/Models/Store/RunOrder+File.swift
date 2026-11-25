extension RunOrder {
  /// The bytes of `run-order.json` exactly as chapter 12 §9 shows them:
  /// `{"order_version":1,"last_run_id":"…"}`, on one line with no line feed.
  var fileBytes: [UInt8] {
    let text = "{\"order_version\":1,\"last_run_id\":\"" + lastRunIdentifier.text + "\"}"

    return Array(text.utf8)
  }
}
