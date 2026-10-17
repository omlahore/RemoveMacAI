import AppKit
import CryptoKit
import Foundation

/// The configuration profile that holds every locked setting: Apple
/// Intelligence, the download block for removed models, and the profile
/// tweaks. Removing the profile undoes all of it.
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

  /// What the profile contains: Apple Intelligence off except the kept
  /// features (nil leaves Apple Intelligence alone), and the profile tweaks.
  struct Contents: Equatable {
    var ai: Set<String>?
    var tweaks: Set<String>

    var isEmpty: Bool { ai == nil && tweaks.isEmpty }
  }

  static func data(keeping kept: Set<String>) throws -> Data {
    try data(Contents(ai: kept, tweaks: installed().tweaks))
  }

  static func data(_ contents: Contents) throws -> Data {
    var restrictions = payload(
      type: "com.apple.applicationaccess", suffix: "restrictions", name: "Restrictions")
    var forced: [String: [String: Any]] = [:]

    if let kept = contents.ai {
      for feature in Catalog.availableFeatures where !kept.contains(feature.id) {
        for key in feature.restrictions { restrictions[key] = false }
        for pref in feature.preferences { forced[pref.domain, default: [:]][pref.key] = pref.off }
      }
      for name in Catalog.setsToRemove(keeping: kept) {
        guard let set = Catalog.modelSet(name) else { continue }
        forced[downloadDomain, default: [:]][downloadKey(set)] = blockedURL
      }
    }
    for tweak in Tweaks.all where contents.tweaks.contains(tweak.id) {
      for change in tweak.changes {
        switch change {
        case .restriction(let key): restrictions[key] = false
        case .forced(let domain, let key, let value): forced[domain, default: [:]][key] = value.object
        default: break
        }
      }
    }
    // A marker of our own, so status can tell the profile is in force and
    // what it was made with.
    var marker: [String: Any] = ["installed": true, "ai": contents.ai != nil, "tweaks": contents.tweaks.sorted().joined(separator: ",")]
    marker["kept"] = (contents.ai ?? []).sorted().joined(separator: ",")
    forced[identifier] = marker
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
        "Turns off Apple Intelligence and the settings chosen in RemoveMacAI, and stops removed models downloading again. Remove this profile to undo.",
      "PayloadOrganization": "RemoveMacAI",
      "PayloadScope": "System",
      "PayloadRemovalDisallowed": false,
    ]
    let hasRestrictions = restrictions.keys.contains { $0.hasPrefix("allow") }
    profile["PayloadContent"] = (hasRestrictions ? [restrictions] : []) + preferences
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

  struct Installed {
    var on = false
    /// Whether the profile turns Apple Intelligence off. Profiles from
    /// before 1.0 only did that, so a missing flag means yes.
    var ai = false
    var kept: Set<String> = []
    var tweaks: Set<String> = []

    var contents: Contents? { on ? Contents(ai: ai ? kept : nil, tweaks: tweaks) : nil }
  }

  /// Whether our profile is in force, and what it holds.
  static func installed() -> Installed {
    let domain = identifier as CFString
    CFPreferencesAppSynchronize(domain)
    guard CFPreferencesAppValueIsForced("installed" as CFString, domain) else { return Installed() }
    func list(_ key: String) -> Set<String> {
      let s = CFPreferencesCopyAppValue(key as CFString, domain) as? String ?? ""
      return Set(s.split(separator: ",").map(String.init))
    }
    let ai = CFPreferencesCopyAppValue("ai" as CFString, domain) as? Bool ?? true
    return Installed(on: true, ai: ai, kept: list("kept"), tweaks: list("tweaks"))
  }

  /// Writes the profile and opens it, so System Settings shows it for approval.
  static func present(_ contents: Contents) throws {
    try data(contents).write(to: file)
    NSWorkspace.shared.open(file)
  }

  static func matches(_ contents: Contents) -> Bool { installed().contents == contents }
}
