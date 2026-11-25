/// The payloads and fingerprints of the conformance vectors of chapter 11 §89.8, copied from the
/// chapter: the bytes the vectors fix.
enum VectorExpectations {
  static let payloadA = [
    #"{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"#,
    #""when":["Perform the action."]}],"fingerprint_version":1,"#,
    #""freshness_policy":{"binding_identity":"content","#,
    #""normalization":{"ignore":["line-endings"]}},"implementation_links":[],"#,
    #""intent":"Demonstrate success.","resources":[],"route":{"covers":["success"],"#,
    #""gates_verification":true,"procedure":{"reset":[],"setup":[],"#,
    #""steps":["Perform the action and observe success."]},"type":{"kind":"acceptance"}},"#,
    #""route_id":"manual","use_case_id":"example.success","validation_links":[]}"#,
  ].joined()

  static let fingerprintA =
    "uc-route-v1-sha256:e909a34e46f252338a7cfee137a5bb0d40ed94f67ba7b85f507ce1af4804e581"

  static let payloadB = [
    #"{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"#,
    #""when":["Perform the action."]}],"fingerprint_version":1,"#,
    #""freshness_policy":{"binding_identity":"content","#,
    #""normalization":{"ignore":["line-endings"]}},"#,
    #""implementation_links":[{"id":"implementation","regions":[{"algorithm":"sha256","#,
    #""byte_length":0,"#,
    #""digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"}]}],"#,
    #""intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","#,
    #""byte_length":2,"#,
    #""digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"#,
    #""file":"fixtures/users.json"}],"route":{"covers":["success"],"#,
    #""gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"#,
    #""route_id":"unit-tests","use_case_id":"example.success","#,
    #""validation_links":[{"id":"success","regions":[{"algorithm":"sha256","#,
    #""byte_length":4,"#,
    #""digest":"e325e71c1fee5ac429847c81d789073ceff87b488b359350282a774dd76ac849"}]}]}"#,
  ].joined()

  static let fingerprintB =
    "uc-route-v1-sha256:7701c45be50ad8d5014cc0b9a224cd78f61b2c3854d59d43473c8640d8b375ee"

  static let payloadC = [
    #"{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"#,
    #""when":["Perform the action."]}],"fingerprint_version":1,"#,
    #""freshness_policy":{"binding_identity":"content-and-locator","#,
    #""normalization":{"ignore":["line-endings"]}},"#,
    #""implementation_links":[{"id":"implementation","kind":"manual","#,
    #""regions":[{"content":{"algorithm":"sha256","byte_length":0,"#,
    #""digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"},"#,
    #""locator":{"end_byte":0,"file":"src/app.swift","start_byte":0}}]}],"#,
    #""intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","#,
    #""byte_length":2,"#,
    #""digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"#,
    #""file":"fixtures/users.json"}],"route":{"covers":["success"],"#,
    #""gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"#,
    #""route_id":"unit-tests","use_case_id":"example.success","#,
    #""validation_links":[{"id":"success","kind":"marker","#,
    #""regions":[{"content":{"algorithm":"sha256","byte_length":4,"#,
    #""digest":"e325e71c1fee5ac429847c81d789073ceff87b488b359350282a774dd76ac849"},"#,
    #""locator":{"end_byte":52,"file":"tests/app_tests.swift","start_byte":48}}]}]}"#,
  ].joined()

  static let fingerprintC =
    "uc-route-v1-sha256:29a534caec5762a5f3e010c19c0bb0525cb16c1ec9f35da2f9117367705e7011"

  static let payloadD = [
    #"{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"#,
    #""when":["Perform the action."]}],"fingerprint_version":1,"#,
    #""freshness_policy":{"binding_identity":"content","#,
    #""normalization":{"ignore":["line-endings"]}},"#,
    #""implementation_links":[{"id":"implementation","regions":[{"algorithm":"sha256","#,
    #""byte_length":0,"#,
    #""digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"}]}],"#,
    #""intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","#,
    #""byte_length":2,"#,
    #""digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"#,
    #""file":"fixtures/users.json"}],"route":{"covers":["success"],"#,
    #""gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"#,
    #""route_id":"unit-tests","use_case_id":"example.success","#,
    #""validation_links":[{"id":"success","regions":[{"algorithm":"sha256","#,
    #""byte_length":31,"#,
    #""digest":"305c89298d281a6dd3feecc816b5e4f98347b1c96e1ea781db6f7338cbe31294"}]}]}"#,
  ].joined()

  static let fingerprintD =
    "uc-route-v1-sha256:1a251529ca94a1cd5649a8a594023287e1f97aa22729f68fccb152936340cdb3"

  static let payloadE = [
    #"{"covered_scenarios":[{"given":[],"id":"success","then":["Success is visible."],"#,
    #""when":["Perform the action."]}],"fingerprint_version":1,"#,
    #""freshness_policy":{"binding_identity":"content-and-locator","#,
    #""normalization":{"ignore":["line-endings"]}},"#,
    #""implementation_links":[{"id":"implementation","kind":"manual","#,
    #""regions":[{"content":{"algorithm":"sha256","byte_length":0,"#,
    #""digest":"e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5"},"#,
    #""locator":{"end_byte":0,"file":"src/app.swift","start_byte":0}}]}],"#,
    #""intent":"Demonstrate success.","resources":[{"content":{"algorithm":"sha256","#,
    #""byte_length":2,"#,
    #""digest":"52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8"},"#,
    #""file":"fixtures/users.json"}],"route":{"covers":["success"],"#,
    #""gates_verification":true,"procedure":null,"type":{"kind":"unit"}},"#,
    #""route_id":"unit-tests","use_case_id":"example.success","#,
    #""validation_links":[{"id":"success","kind":"marker","#,
    #""regions":[{"content":{"algorithm":"sha256","byte_length":8,"#,
    #""digest":"52d0f4b311a9e006bde69e359deb00f6291a10e1bfbf23c18a1c93613984c491"},"#,
    #""locator":{"end_byte":126,"file":"tests/app_tests.swift","start_byte":48}}]}]}"#,
  ].joined()

  static let fingerprintE =
    "uc-route-v1-sha256:af91ac81aba75c48283b27ee159ca8776bb44ada1901592c555eb7f366f2d632"
}
