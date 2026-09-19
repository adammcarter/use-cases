/// Sorting as V8 sorts the lists the showcase TypeScript sorts.
extension ShowcaseJavaScript {
  /// `events.slice().sort((left, right) => left.sequence - right.sequence)`,
  /// in V8's own algorithm so a comparator answering NaN — a sequence that is
  /// not a number — orders events as V8 does. Lists of fewer than 64 elements
  /// follow V8's short-list path exactly (``insertionSort(_:compare:)``).
  /// Longer lists are merged stably, which agrees with V8 whenever every
  /// sequence is a number, and may not when one is not.
  static func sortedBySequence(_ events: [JSONValue]) throws(ShowcaseError) -> [JSONValue] {
    guard events.count > 1 else {
      return events
    }
    var sequences: [Double] = []
    for event in events {
      try sequences.append(toNumber(member(event, "sequence")))
    }
    var order = Array(events.indices)
    let compare: (Int, Int) -> Double = { left, right in
      sequences[left] - sequences[right]
    }
    if order.count < 64 {
      insertionSort(&order, compare: compare)
    } else {
      order = mergeSorted(order) { left, right in
        compare(left, right) < 0
      }
    }
    return order.map { events[$0] }
  }

  /// V8's sort of a short list, as node 26 (V8 14.6) runs it and as measured
  /// against its comparator call sequence over 4,800 random lists of 2 to 63
  /// elements with NaN results: below 8 elements, binary insertion from the
  /// second element; from 8, a leading run is counted first — descending when
  /// the first comparison is `< 0`, an ascending run ending at a `< 0`, a
  /// descending one at anything not `< 0` (NaN included) — reversed if
  /// descending, and binary insertion extends it.
  private static func insertionSort(
    _ work: inout [Int],
    compare: (Int, Int) -> Double,
  ) {
    var runLength = 1
    if work.count >= 8 {
      runLength = 2
      let isDescending = compare(work[1], work[0]) < 0
      var previous = work[1]
      var index = 2
      while index < work.count {
        let current = work[index]
        let isLess = compare(current, previous) < 0
        if isDescending ? !isLess : isLess {
          break
        }
        previous = current
        runLength += 1
        index += 1
      }
      if isDescending {
        work[0 ..< runLength].reverse()
      }
    }
    var start = runLength
    while start < work.count {
      let pivot = work[start]
      var left = 0
      var right = start
      while left < right {
        let middle = left + (right - left) / 2
        if compare(pivot, work[middle]) < 0 {
          right = middle
        } else {
          left = middle + 1
        }
      }
      var position = start
      while position > left {
        work[position] = work[position - 1]
        position -= 1
      }
      work[left] = pivot
      start += 1
    }
  }

  private static func mergeSorted(
    _ items: [Int],
    precedes: (Int, Int) -> Bool,
  ) -> [Int] {
    guard items.count > 1 else {
      return items
    }
    let middle = items.count / 2
    let left = mergeSorted(Array(items[..<middle]), precedes: precedes)
    let right = mergeSorted(Array(items[middle...]), precedes: precedes)
    var merged: [Int] = []
    merged.reserveCapacity(items.count)
    var leftIndex = 0
    var rightIndex = 0
    while leftIndex < left.count, rightIndex < right.count {
      if precedes(right[rightIndex], left[leftIndex]) {
        merged.append(right[rightIndex])
        rightIndex += 1
      } else {
        merged.append(left[leftIndex])
        leftIndex += 1
      }
    }
    merged += left[leftIndex...]
    merged += right[rightIndex...]
    return merged
  }

  /// A bare `.sort()`: `undefined` last, everything else by the code units of
  /// its string form, stably.
  static func sortedAsStrings(_ values: [JSONValue?]) -> [JSONValue?] {
    let present = values.compactMap(\.self)
    let absent = values.count - present.count
    let sorted = present.enumerated()
      .sorted { left, right in
        let leftText = JavaScriptString.text(of: left.element)
        let rightText = JavaScriptString.text(of: right.element)
        if JavaScriptString.precedes(leftText, rightText) {
          return true
        }
        if JavaScriptString.precedes(rightText, leftText) {
          return false
        }
        return left.offset < right.offset
      }
      .map { entry in
        Optional(entry.element)
      }
    return sorted + Array(repeating: nil, count: absent)
  }
}
