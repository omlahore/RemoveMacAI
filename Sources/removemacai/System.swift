import Foundation
import UAF

/// Apple's asset service: how much of each model set is on disk, and removing it.
enum Models {
  static func available() -> Bool {
    UAFLoad() && UAFAssetType(Catalog.foundationModels) != nil
  }

  /// What the asset service has installed and who asks for it. On macOS 27.0.1
  /// the per-set status reports 0 bytes for every set, so sizes come from here.
  struct Inventory {
    var bytes: [String: Int64] = [:]  // by asset type, assets present on disk
    var assets: [String: Int] = [:]
    var subscribers: [String: Set<String>] = [:]  // by set name
    var usages: [String: Int] = [:]  // by set name, usages the system wants now
  }

  private static var cached: (at: Date, value: Inventory?)?

  static func inventory() -> Inventory? {
    if let c = cached, Date().timeIntervalSince(c.at) < 1 { return c.value }
    var error: NSError?
    var inv: Inventory?
    if UAFLoad(), let info = UAFInformation(&error) {
      var i = Inventory()
      for asset in info["SystemAssets"] as? [[String: Any]] ?? [] {
        guard asset["isPresentOnDevice"] as? Bool == true,
          let meta = asset["metadata"] as? [String: Any],
          let type = meta["AssetType"] as? String
        else { continue }
        let size = meta["com.apple.UnifiedAssetFramework.UnarchivedSize"] ?? meta["_UnarchivedSize"]
        i.bytes[type, default: 0] += Int64("\(size ?? 0)") ?? 0
        i.assets[type, default: 0] += 1
      }
      for (_, clients) in info["Subscriptions"] as? [String: [String: [[String: Any]]]] ?? [:] {
        for (client, subscriptions) in clients {
          for s in subscriptions {
            for set in (s["assetSets"] as? [String: Any] ?? [:]).keys {
              i.subscribers[set, default: []].insert(client)
            }
          }
        }
      }
      for (set, list) in info["SystemAssetSetUsages"] as? [String: [Any]] ?? [:] {
        i.usages[set] = list.count
      }
      inv = i
    }
    cached = (Date(), inv)
    return inv
  }

  /// Bytes on disk the asset service tracks for a set, or nil when it does not say.
  static func bytes(_ set: String) -> Int64? {
    if let model = Catalog.modelSet(set), let inv = inventory() {
      return inv.bytes[model.assetType] ?? 0
    }
    var error: NSError?
    let n = UAFDownloadedBytes(set, &error)
    return n >= 0 ? n : nil
  }

  static func total(_ sets: [String]) -> Int64 { sets.compactMap(bytes).reduce(0, +) }

  /// The set's folder in the asset store. It can hold files the service no
  /// longer tracks (older instances waiting for cleanup), which System
  /// Settings still counts.
  static func folder(_ set: ModelSet) -> URL {
    URL(fileURLWithPath: "/System/Library/AssetsV2/"
      + set.assetType.replacingOccurrences(of: ".", with: "_"))
  }

  static func folderExists(_ set: String) -> Bool {
    guard let model = Catalog.modelSet(set) else { return false }
    return FileManager.default.fileExists(atPath: folder(model).path)
  }

  /// Size of the set's folder, or nil when macOS will not let us read it
  /// (it needs root, and some folders refuse even that).
  static func folderBytes(_ set: String) -> Int64? {
    guard let model = Catalog.modelSet(set) else { return nil }
    let url = folder(model)
    guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil,
      let walk = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [],
        errorHandler: { _, _ in true })
    else { return nil }
    var total: Int64 = 0
    for case let file as URL in walk {
      total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
    }
    return total
  }

  /// Whether anything of the set may still be on disk. A folder we cannot
  /// read counts, since that is where the untracked models sit; one we can
  /// read counts only when it holds something.
  static func present(_ set: String) -> Bool {
    if (bytes(set) ?? 0) > 0 { return true }
    guard folderExists(set) else { return false }
    return (folderBytes(set) ?? 1) > 0
  }

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
    return profile.on && profile.current && !profile.kept.contains(feature.id)
  }

  static func isForced(_ domain: String, _ key: String, value: Bool) -> Bool {
    CFPreferencesAppSynchronize(domain as CFString)
    return CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
      && self.value(domain, key) == value
  }

  static func isForcedString(_ domain: String, _ key: String) -> Bool {
    CFPreferencesAppSynchronize(domain as CFString)
    return CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
  }

  static func value(_ domain: String, _ key: String) -> Bool? {
    CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
  }
}

struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
