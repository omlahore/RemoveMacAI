import Foundation

/// The macOS update Software Update has found, read from its own preferences,
/// so asking makes no network request.
enum PendingUpdate {
  static func name() -> String? {
    let prefs = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") as? [String: Any]
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let running = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
    return name(in: prefs ?? [:], running: running)
  }

  static func name(in prefs: [String: Any], running: String) -> String? {
    for update in prefs["RecommendedUpdates"] as? [[String: Any]] ?? [] {
      guard let name = update["Display Name"] as? String, name.hasPrefix("macOS"),
        update["Display Version"] as? String != running
      else { continue }
      return name
    }
    return nil
  }

  /// The update to warn about: one that's waiting while the profile blocks model
  /// downloads, because Software Update retries those before it installs (#109).
  static func slowedBy(_ profile: Profile.Installed) -> String? {
    guard profile.on, profile.ai, !Catalog.setsToRemove(keeping: profile.kept).isEmpty else { return nil }
    return name()
  }
}
