import AppKit
import Foundation

/// The in-app language choice. It writes the standard `AppleLanguages`
/// preference and relaunches so every string, including SwiftUI's own
/// `LocalizedStringKey` and `String(localized:)`, picks up the change.
enum AppLanguage: String, CaseIterable, Identifiable, Hashable {
  case system
  case english
  case chinese
  case russian

  var id: String { rawValue }

  var code: String? {
    switch self {
    case .system: return nil
    case .english: return "en"
    case .chinese: return "zh-Hans"
    case .russian: return "ru"
    }
  }

  /// Each language is written in its own script; the System option follows the app.
  var nativeName: String {
    switch self {
    case .system: return L("System")
    case .english: return "English"
    case .chinese: return "简体中文"
    case .russian: return "Русский"
    }
  }

  static var current: AppLanguage {
    let codes = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
    switch codes.first {
    case "en", "en-US", "en-GB": return .english
    case "zh-Hans", "zh-CN", "zh": return .chinese
    case "ru": return .russian
    default: return .system
    }
  }

  static func apply(_ language: AppLanguage) {
    if let code = language.code {
      UserDefaults.standard.set([code], forKey: "AppleLanguages")
    } else {
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }
    relaunch()
  }

  private static func relaunch() {
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      NSApp.terminate(nil)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
      NSApp.terminate(nil)
    }
  }
}
