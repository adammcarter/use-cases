/// Builds the lines of `go test -json`.
enum GoTestStream {
  static func event(
    _ action: String,
    _ test: String?,
    package: String = "example.com/shop/cart",
  ) -> String {
    var fields: [String: Any] = ["Action": action, "Package": package]

    fields["Test"] = test

    return jsonLine(fields)
  }
}
