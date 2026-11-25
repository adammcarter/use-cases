import Foundation
#if canImport(FoundationXML)
  import FoundationXML
#endif

/// The test cases of one JUnit XML file, in document order.
struct JUnitReport: Equatable, Sendable {
  let cases: [JUnitCase]

  /// Reads `data`, the XML written to `path`; malformed XML is an error, never a guess.
  init(
    data: Data,
    path: String,
  ) throws(TransformerFailure) {
    let collector = JUnitCaseCollector()
    let parser = XMLParser(data: data)

    parser.delegate = collector

    // Foundation on Linux can report an error to the delegate and still answer true, and says
    // nothing about a document with no element, so all three are asked.
    let isWhole = parser.parse() && collector.failure == nil && collector.isComplete

    guard isWhole else {
      let failure = parser.parserError ?? collector.failure
      throw .reportMalformed(
        path: path,
        reason: failure?.localizedDescription ?? "not XML",
      )
    }

    cases = collector.cases
  }
}

private final class JUnitCaseCollector: NSObject, XMLParserDelegate {
  private(set) var cases: [JUnitCase] = []
  private(set) var failure: (any Error)?
  private var open: OpenCase?
  private var depth = 0
  private var hasRoot = false

  /// Whether the document had a root element and every element it opened was closed.
  var isComplete: Bool {
    hasRoot && depth == 0
  }

  private struct OpenCase {
    let attributes: [String: String]
    let depth: Int
    var children: Set<String> = []
  }

  func parser(
    _: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes attributeDict: [String: String] = [:],
  ) {
    depth += 1
    hasRoot = true

    if elementName == "testcase", open == nil {
      open = OpenCase(
        attributes: attributeDict,
        depth: depth,
      )
    } else if open != nil, depth == (open?.depth ?? 0) + 1 {
      open?.children.insert(elementName)
    }
  }

  func parser(
    _: XMLParser,
    didEndElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
  ) {
    if elementName == "testcase", let finished = open, finished.depth == depth {
      cases.append(
        JUnitCase(
          className: finished.attributes["classname"] ?? "",
          name: finished.attributes["name"] ?? "",
          file: finished.attributes["file"],
          line: finished.attributes["line"],
          statusAttribute: finished.attributes["status"],
          children: finished.children,
        ),
      )
      open = nil
    }

    depth -= 1
  }

  func parser(
    _: XMLParser,
    parseErrorOccurred parseError: any Error,
  ) {
    failure = failure ?? parseError
  }
}
