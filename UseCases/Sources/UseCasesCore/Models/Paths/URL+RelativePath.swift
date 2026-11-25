import Foundation

extension URL {
  /// The path from `base` to this location, written with `/`: `.` for the same place, `..` for
  /// each folder to climb. Both are read as they are spelled, so canonical locations in, a path
  /// that is right out.
  func relativePath(from base: URL) -> String {
    let target = pathComponents.filter { $0 != "/" }
    let start = base.pathComponents.filter { $0 != "/" }
    let shared = zip(target, start).prefix { pair in
      pair.0 == pair.1
    }.count

    let steps = Array(repeating: "..", count: start.count - shared) + target.dropFirst(shared)

    return steps.isEmpty ? "." : steps.joined(separator: "/")
  }
}
