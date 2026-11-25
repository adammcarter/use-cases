import Foundation

/// One JSON value written on one line, keys in name order.
func jsonLine(_ object: Any) -> String {
  let data = (try? JSONSerialization.data(
    withJSONObject: object,
    options: [.sortedKeys, .withoutEscapingSlashes],
  )) ?? Data()

  return String(
    data: data,
    encoding: .utf8,
  ) ?? ""
}
