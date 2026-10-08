import Foundation

enum MusicLaunch {
  static let prefix = "application.com.apple.Music."
  /// The self-test substitutes a temporary bundle.
  static var app = URL(fileURLWithPath: "/System/Applications/Music.app")

  /// LaunchServices uses the bundle and executable inode numbers in this
  /// application-job label (verified against launchctl on macOS 27.0.1).
  /// Resolve it without opening Music; OS updates can change either inode.
  static func label() throws -> String {
    func inode(_ url: URL) throws -> String {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let number = attributes[.systemFileNumber] as? NSNumber else {
        throw Failure("could not read the file number of \(url.path)")
      }
      return number.stringValue
    }
    return try prefix + inode(app) + "." + inode(app.appendingPathComponent("Contents/MacOS/Music"))
  }

  static func state(disabled: Set<String>) -> TweakState {
    if let current = try? label(), disabled.contains(current) {
      // If bootout failed, reapply must still be able to close the running app.
      return Engine.launchctl(["print", "gui/\(Engine.uid)/\(current)"]).ok ? .partial : .applied
    }
    // Keep stale entries visible so an update can be followed by apply or undo.
    return disabled.contains(where: { $0.hasPrefix(prefix) }) ? .partial : .notApplied
  }

  static func recordedLabels(_ tweak: String, journal: Engine.Journal) -> [String] {
    journal.entries.compactMap { key, entry in
      guard entry.tweak == tweak, key.hasPrefix("service:" + prefix),
        case .service = entry.previous else { return nil }
      return String(key.dropFirst("service:".count))
    }.sorted()
  }
}
