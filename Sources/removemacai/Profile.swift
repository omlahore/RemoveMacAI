import CryptoKit
import Foundation

/// The configuration profile that switches the features off and stops macOS
/// downloading the removed models again. Removing the profile undoes all of it.
enum Profile {
  static let identifier = "io.github.omlahore.removemacai"
  static let file = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Downloads/RemoveMacAI.mobileconfig")

  // Point the asset service at a closed local port for each removed set, so a
  // download fails instead of refilling the disk (technique from pared).
  static let downloadDomain = "com.apple.MobileAsset"
  static let downloadKeyPrefix = "DownloadServerBaseURLOverride-"
  static let blockedURL = "https://127.0.0.1:9/removemacai-blocked/"

  static func downloadKey(_ set: ModelSet) -> String { downloadKeyPrefix + set.assetType }

  static func data(keeping kept: Set<String>) throws -> Data {
    let off = Catalog.features.filter { !kept.contains($0.id) }
    var restrictions = payload(
      type: "com.apple.applicationaccess", suffix: "restrictions",
      name: "Apple Intelligence restrictions")
    for feature in off {
      for key in feature.restrictions { restrictions[key] = false }
    }

    var forced: [String: [String: Any]] = [:]
    for feature in off {
      for pref in feature.preferences { forced[pref.domain, default: [:]][pref.key] = pref.off }
    }
    for name in Catalog.setsToRemove(keeping: kept) {
      guard let set = Catalog.modelSet(name) else { continue }
      forced[downloadDomain, default: [:]][downloadKey(set)] = blockedURL
    }
    // A marker of our own, so status can tell the profile is in force and
    // what it was made with.
    forced[identifier] = [
      "installed": true, "kept": kept.sorted().joined(separator: ","), "revision": revision,
    ]
    let preferences = forced.keys.sorted().map { domain -> [String: Any] in
      var p = payload(
        type: "com.apple.ManagedClient.preferences", suffix: "preferences." + domain,
        name: "Forced settings: \(domain)")
      p["PayloadContent"] = [domain: ["Forced": [["mcx_preference_settings": forced[domain]!]]]]
      return p
    }

    var profile: [String: Any] = [
      "PayloadType": "Configuration",
      "PayloadVersion": 1,
      "PayloadIdentifier": identifier,
      "PayloadUUID": uuid(identifier),
      "PayloadDisplayName": "RemoveMacAI",
      "PayloadDescription":
        "Turns Apple Intelligence off and stops its models downloading again. Remove this profile to undo.",
      "PayloadOrganization": "RemoveMacAI",
      "PayloadScope": "System",
      "PayloadRemovalDisallowed": false,
    ]
    profile["PayloadContent"] = [restrictions] + preferences
    return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
  }

  private static func payload(type: String, suffix: String, name: String) -> [String: Any] {
    let id = identifier + "." + suffix
    return [
      "PayloadType": type, "PayloadVersion": 1, "PayloadIdentifier": id,
      "PayloadUUID": uuid(id), "PayloadDisplayName": name,
    ]
  }

  /// A stable UUID per payload (version 5 style, from its identifier), so
  /// installing a new version replaces the old one.
  static func uuid(_ name: String) -> String {
    var bytes = Array(Insecure.SHA1.hash(data: Data(name.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
  }

  /// A fingerprint of everything the profile switches, so a profile made by
  /// an older catalog counts as out of date and is replaced.
  static let revision: String = {
    let parts = Catalog.features.map { f in
      ([f.id] + f.restrictions + f.preferences.map { "\($0.domain)/\($0.key)=\($0.off)" } + f.modelSets)
        .joined(separator: "|")
    } + Catalog.modelSets.map { "\($0.name)=\($0.assetType)" }
    return Insecure.SHA1.hash(data: Data(parts.joined(separator: "\n").utf8))
      .prefix(6).map { String(format: "%02x", $0) }.joined()
  }()

  /// Whether our profile is in force, the features it was told to keep, and
  /// whether it was made from this catalog.
  static func installed() -> (on: Bool, kept: Set<String>, current: Bool) {
    let domain = identifier as CFString
    CFPreferencesAppSynchronize(domain)
    guard CFPreferencesAppValueIsForced("installed" as CFString, domain) else { return (false, [], false) }
    let kept = CFPreferencesCopyAppValue("kept" as CFString, domain) as? String ?? ""
    let made = CFPreferencesCopyAppValue("revision" as CFString, domain) as? String
    return (true, Set(kept.split(separator: ",").map(String.init)), made == revision)
  }
}
