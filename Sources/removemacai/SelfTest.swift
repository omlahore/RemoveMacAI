import Foundation
import UAF

/// Checks the parts that must never go wrong, runnable without Xcode:
/// `removemacai selftest`. Touches nothing on the system.
func selfTest() -> Bool {
  var failed = 0
  func check(_ ok: Bool, _ what: String) {
    print((ok ? Term.green("pass ") : Term.red("FAIL ")) + what)
    if !ok { failed += 1 }
  }
  func throwsFailure(_ body: () throws -> Void) -> Bool {
    do { try body() } catch is Failure { return true } catch { return false }
    return false
  }

  check(Set(Catalog.setsToRemove(keeping: [])) == Set(Catalog.modelSets.map(\.name)),
    "off removes every model set")
  let keptWriting = Catalog.setsToRemove(keeping: ["writing-tools"])
  check(!keptWriting.contains(Catalog.foundationModels) && keptWriting.contains(Catalog.spatialModels),
    "a kept feature keeps the models it needs, and only those")
  check(Catalog.setsToRemove(keeping: Set(Catalog.features.map(\.id))).isEmpty,
    "keeping everything removes nothing")
  check(Catalog.features.allSatisfy { $0.modelSets.allSatisfy { Catalog.modelSet($0) != nil } },
    "every model set a feature names is in the catalog")
  check(Set(Catalog.features.map(\.id)).count == Catalog.features.count, "feature names are unique")
  check(Set(Catalog.modelSets.map(\.assetType)).count == Catalog.modelSets.count, "asset types are unique")
  if Models.available() {
    let wrong = Catalog.modelSets.filter { UAFAssetType($0.name) != $0.assetType }
    check(wrong.isEmpty, "every model set has the asset type macOS reports"
      + (wrong.isEmpty ? "" : ": " + wrong.map { "\($0.name) is \(UAFAssetType($0.name) ?? "unknown")" }.joined(separator: ", ")))
  }
  check(throwsFailure { try Models.remove([]) }, "an empty removal is refused before anything is sent")
  check(throwsFailure { try Models.remove(["com.apple.something.else"]) }, "an unknown set is refused")

  do {
    let plist = try PropertyListSerialization.propertyList(from: Profile.data(keeping: []), format: nil)
      as! [String: Any]
    let payloads = plist["PayloadContent"] as! [[String: Any]]
    let restrictions = payloads.first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }!
    check(restrictions["allowWritingTools"] as? Bool == false && restrictions["allowAssistant"] as? Bool == false,
      "the profile turns Writing Tools and Siri off")
    let blocks = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".com.apple.MobileAsset") == true }!
    let content = (blocks["PayloadContent"] as! [String: Any])["com.apple.MobileAsset"] as! [String: Any]
    let settings = ((content["Forced"] as! [[String: Any]])[0]["mcx_preference_settings"]) as! [String: String]
    check(settings.count == Catalog.modelSets.count && settings.values.allSatisfy { $0.hasPrefix("https://127.0.0.1:9/") },
      "the profile blocks downloads for every removed set")
    let uuids = payloads.compactMap { $0["PayloadUUID"] as? String } + [plist["PayloadUUID"] as! String]
    check(Set(uuids).count == uuids.count && Profile.uuid("a") == Profile.uuid("a"),
      "payload UUIDs are unique and stable")

    let keep = try PropertyListSerialization.propertyList(from: Profile.data(keeping: ["writing-tools"]), format: nil)
      as! [String: Any]
    let kr = (keep["PayloadContent"] as! [[String: Any]]).first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }!
    check(kr["allowWritingTools"] == nil && kr["allowGenmoji"] as? Bool == false, "a kept feature is left alone")
  } catch {
    check(false, "the profile builds: \(error)")
  }
  print(failed == 0 ? Term.green("all checks passed") : Term.red("\(failed) failed"))
  return failed == 0
}
