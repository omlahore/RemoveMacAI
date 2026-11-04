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
  /// the catalog <folder>.xml and its .purged copy. Anything else, a count
  /// macOS will not give, or a purpose_auto that changes while it is checked,
  /// counts as files. Only a folder that is surely missing counts as empty.
  static func folderHoldsFiles(_ assetType: String, root: String = "/System/Library/AssetsV2") -> Bool {
    let name = assetType.replacingOccurrences(of: ".", with: "_")
    let folder = root + "/" + name
    var info = stat()
    if lstat(folder, &info) != 0 { return errno != ENOENT }
    let files = FileManager.default
    guard let top = entryCount(folder) else { return true }
    let purpose = folder + "/purpose_auto"
    guard files.fileExists(atPath: purpose) else { return top > 0 }
    guard let before = modified(purpose), let inner = entryCount(purpose) else { return true }
    let catalog = [name + ".xml", name + ".xml.purged"].filter { files.fileExists(atPath: purpose + "/" + $0) }
    guard let after = modified(purpose), after == before else { return true }
    return top > 1 || inner > catalog.count
  }

  /// Entries in a folder, from its attributes rather than a listing, or nil.
  /// Anything but a folder gets no count back, so it gets nil too.
  static func entryCount(_ path: String) -> Int? {
    var request = attrlist()
    request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    request.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
    var reply: (length: UInt32, count: UInt32) = (0, 0)
    let status = withUnsafeMutableBytes(of: &reply) { getattrlist(path, &request, $0.baseAddress, $0.count, 0) }
    return status == 0 && reply.length >= UInt32(MemoryLayout.size(ofValue: reply)) ? Int(reply.count) : nil
  }

  /// When a folder's entries last changed, or nil.
  static func modified(_ path: String) -> (seconds: Int, nanoseconds: Int)? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return (info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec)
  }

  /// A total is only known when every selected set answered.
  static func total(_ sets: [String], read: (String) -> Int64? = bytes) -> Int64? {
    var total: Int64 = 0
    for set in sets {
      guard let bytes = read(set) else { return nil }
      total += bytes
    }
    return total
  }

  /// Splits the sets into those whose asset type still matches the catalog and
  /// those to leave alone, with the reason. Refuses anything outside the catalog.
  static func matching(_ sets: [String], assetType: (String) -> String? = UAFAssetType) throws
    -> (matched: [String], skipped: [(String, String)])
  {
    var matched: [String] = []
    var skipped: [(String, String)] = []
    for name in sets {
      guard let known = Catalog.modelSet(name) else { throw Failure("unknown model set \(name)") }
      let type = assetType(name)
      if type == known.assetType {
        matched.append(name)
      } else if let type {
        skipped.append((name, "its asset type is \(type) on this version of macOS, so it was left alone"))
      } else {
        skipped.append((name, "not found on this version of macOS, so it was left alone"))
      }
    }
    return (matched, skipped)
  }

  /// Removes the downloaded models of these sets, one set per request, so one
  /// the service rejects does not stop the rest. Refuses anything outside the
  /// catalog, and leaves alone any set whose asset type no longer matches it.
  /// Returns the sets that stayed, with the reason.
  @discardableResult
  static func remove(_ sets: [String], timeout: TimeInterval = 120, retryDelays: [TimeInterval] = [5, 15]) throws
    -> [(String, String)]
  {
    guard !sets.isEmpty else { throw Failure("no model sets selected") }
    var (matched, failed) = try matching(sets)
    for name in matched where present(name) {
      switch retrying({ reset(name, timeout: timeout) }, delays: retryDelays) {
      case .done: break
      case .locked: failed.append((name, lockedReason))
      case .noAnswer: failed.append((name, "no answer in \(Int(timeout)) seconds"))
      case .failed(let reason): if present(name) { failed.append((name, reason)) }
      }
    }
    return failed
  }

  /// Asks again after each delay while the set is locked.
  static func retrying(
    _ attempt: () -> ResetOutcome, delays: [TimeInterval], sleep: (TimeInterval) -> Void = Thread.sleep
  ) -> ResetOutcome {
    var outcome = attempt()
    for delay in delays where outcome == .locked {
      sleep(delay)
      outcome = attempt()
    }
    return outcome
  }

  static let lockedReason =
    "macOS is still using these models, so it wouldn't delete them yet. Restart your Mac, then run RemoveMacAI again to delete them."

  enum ResetOutcome: Equatable {
    case done, locked, noAnswer
    case failed(String)
  }

  static func reset(_ name: String, timeout: TimeInterval) -> ResetOutcome {
    let done = DispatchSemaphore(value: 0)
    var failure: NSError?
    UAFResetAssetSets([name]) { error in
      failure = error as NSError?
      done.signal()
    }
    if done.wait(timeout: .now() + timeout) != .success { return .noAnswer }
    guard let failure else { return .done }
    return isLocked(failure) ? .locked : .failed("\(failure.localizedDescription) (\(failure.domain) \(failure.code))")
  }

  /// The asset service refuses while something on the Mac holds the set.
  static func isLocked(_ error: NSError) -> Bool {
    error.userInfo["currentLockUsage"] != nil || error.localizedDescription.contains("current locks")
  }
}

/// Whether a feature is off, and whether our profile locks it off.
enum FeatureState: Equatable {
  case lockedOff, off, on, unknown

  var isOff: Bool { self == .lockedOff || self == .off }
}

/// The final verification snapshot, kept separate from reset acknowledgements.
struct ModelRemovalResult {
  let before: Int64?
  let after: Int64?
  let failures: [(String, String)]
  let verified: Bool

  var complete: Bool { failures.isEmpty && verified && after == 0 }

  var deletedBytes: Int64? {
    guard let before, let after else { return nil }
    return max(0, before - after)
  }
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
      return modelState(feature.modelSets)
    }
    return .on
  }

  static func modelState(_ sets: [String], read: (String) -> Int64? = Models.bytes) -> FeatureState {
    let readings = sets.map(read)
    if readings.contains(where: { ($0 ?? 0) > 0 }) { return .on }
    return readings.allSatisfy { $0 == 0 } ? .off : .unknown
  }

  /// Features with no switch of their own (only models) count as locked off
  /// while our profile keeps their models from downloading.
  static func lockedByProfile(_ feature: Feature) -> Bool {
    guard feature.restrictions.isEmpty, feature.preferences.isEmpty else { return false }
    let profile = Profile.installed()
    return profile.on && profile.ai && !profile.kept.contains(feature.id)
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
