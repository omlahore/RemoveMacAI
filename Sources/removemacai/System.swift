import Foundation
import UAF

/// Apple's asset service: how much of each model set is on disk, and removing it.
enum Models {
  static func available() -> Bool {
    UAFLoad() && UAFAssetType(Catalog.foundationModels) != nil
  }

  /// Bytes on disk for a set, or nil when the service does not say. The
  /// inventory comes first: the per-set status can report 0 for installed sets.
  static func bytes(_ set: String) -> Int64? {
    if let model = Catalog.modelSet(set), let inventory = inventory() {
      return inventory[model.assetType] ?? 0
    }
    var error: NSError?
    let n = UAFDownloadedBytes(set, &error)
    return n >= 0 ? n : nil
  }

  /// Bytes of present assets by asset type, from the asset service's inventory.
  static func parseInventory(_ info: [String: Any]) -> [String: Int64] {
    var bytes: [String: Int64] = [:]
    for asset in info["SystemAssets"] as? [[String: Any]] ?? [] {
      guard asset["isPresentOnDevice"] as? Bool == true,
        let meta = asset["metadata"] as? [String: Any],
        let type = meta["AssetType"] as? String
      else { continue }
      let size = meta["com.apple.UnifiedAssetFramework.UnarchivedSize"] ?? meta["_UnarchivedSize"]
      bytes[type, default: 0] += Int64("\(size ?? 0)") ?? 0
    }
    return bytes
  }

  private static var cached: (at: Date, value: [String: Int64]?)?

  static func inventory() -> [String: Int64]? {
    if let c = cached, Date().timeIntervalSince(c.at) < 1 { return c.value }
    var error: NSError?
    let value = UAFLoad() ? UAFInformation(&error).map { parseInventory($0 as? [String: Any] ?? [:]) } : nil
    cached = (Date(), value)
    return value
  }

  /// Whether anything of the set may still be on disk: tracked bytes, or files
  /// in its asset folder.
  static func present(_ set: String) -> Bool {
    if (bytes(set) ?? 0) > 0 { return true }
    guard let model = Catalog.modelSet(set) else { return false }
    return folderHoldsFiles(model.assetType)
  }

  /// Whether a set's asset folder may still hold model files. macOS will not
  /// list some of these folders, even to an admin, but it still says how many
  /// entries a folder has and whether a named entry exists, so only those are
  /// used. Once the models are removed, a folder keeps at most purpose_auto with
  /// the catalog <folder>.xml and its .purged copy. Anything else, or a count
  /// macOS will not give, counts as files.
  static func folderHoldsFiles(_ assetType: String, root: String = "/System/Library/AssetsV2") -> Bool {
    let name = assetType.replacingOccurrences(of: ".", with: "_")
    let folder = root + "/" + name
    let files = FileManager.default
    guard files.fileExists(atPath: folder) else { return false }
    guard let top = entryCount(folder) else { return true }
    let purpose = folder + "/purpose_auto"
    guard files.fileExists(atPath: purpose) else { return top > 0 }
    guard let inner = entryCount(purpose) else { return true }
    let catalog = [name + ".xml", name + ".xml.purged"].filter { files.fileExists(atPath: purpose + "/" + $0) }
    return top > 1 || inner > catalog.count
  }

  /// Entries in a folder, from its attributes rather than a listing, or nil.
  static func entryCount(_ path: String) -> Int? {
    var request = attrlist()
    request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    request.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
    var reply: (length: UInt32, count: UInt32) = (0, 0)
    let status = withUnsafeMutableBytes(of: &reply) { getattrlist(path, &request, $0.baseAddress, $0.count, 0) }
    return status == 0 ? Int(reply.count) : nil
  }

  static func total(_ sets: [String]) -> Int64 { sets.compactMap(bytes).reduce(0, +) }

  /// Removes the downloaded models of these sets, one set per request, so one
  /// the service rejects does not stop the rest. Refuses anything outside the
  /// catalog, and any set whose asset type no longer matches it. Returns the
  /// sets that failed, with the reason.
  @discardableResult
  static func remove(_ sets: [String], timeout: TimeInterval = 120) throws -> [(String, String)] {
    guard !sets.isEmpty else { throw Failure("no model sets selected") }
    for name in sets {
      guard let known = Catalog.modelSet(name) else { throw Failure("unknown model set \(name)") }
      guard UAFAssetType(name) == known.assetType else {
        throw Failure("\(name) no longer matches this version of RemoveMacAI; nothing removed")
      }
    }
    var failed: [(String, String)] = []
    for name in sets where present(name) {
      let done = DispatchSemaphore(value: 0)
      var failure: NSError?
      UAFResetAssetSets([name]) { error in
        failure = error as NSError?
        done.signal()
      }
      if done.wait(timeout: .now() + timeout) != .success {
        failed.append((name, "no answer in \(Int(timeout)) seconds"))
      } else if let failure {
        let detail = failure.userInfo.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        failed.append((name, "\(failure.domain) \(failure.code) \(detail)"))
      }
    }
    return failed
  }
}

/// Whether a feature is off, and whether our profile locks it off.
enum FeatureState: Equatable {
  case lockedOff, off, on
}

enum Settings {
  static func state(_ feature: Feature) -> FeatureState {
    let forced =
      feature.restrictions.allSatisfy { isForced("com.apple.applicationaccess", $0, value: false) }
      && feature.preferences.allSatisfy { isForced($0.domain, $0.key, value: $0.off) }
    let locked = forced && (!feature.restrictions.isEmpty || !feature.preferences.isEmpty)
    if locked || lockedByProfile(feature) { return .lockedOff }
    if !feature.preferences.isEmpty,
      feature.preferences.allSatisfy({ value($0.domain, $0.key) == $0.off })
    {
      return .off
    }
    // A feature that is only models is on while its models are on disk.
    if feature.restrictions.isEmpty && feature.preferences.isEmpty {
      return feature.modelSets.contains { (Models.bytes($0) ?? 0) > 0 } ? .on : .off
    }
    return .on
  }

  /// Features with no switch of their own (only models) count as locked off
  /// while our profile keeps their models from downloading.
  static func lockedByProfile(_ feature: Feature) -> Bool {
    guard feature.restrictions.isEmpty, feature.preferences.isEmpty else { return false }
    let profile = Profile.installed()
    return profile.on && !profile.kept.contains(feature.id)
  }

  static func isForced(_ domain: String, _ key: String, value: Bool) -> Bool {
    CFPreferencesAppSynchronize(domain as CFString)
    return CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
      && self.value(domain, key) == value
  }

  static func value(_ domain: String, _ key: String) -> Bool? {
    CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
  }
}

struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
