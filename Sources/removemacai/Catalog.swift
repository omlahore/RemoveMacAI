import Foundation

/// A preference the profile forces while a feature is off.
struct ForcedPreference: Equatable {
  let domain: String
  let key: String
  let off: Bool
}

/// One thing a person can switch off, the switches it takes, and the model
/// sets it needs. Keys and sets for macOS 27 were first mapped by pared
/// (github.com/4evy/pared, MIT).
struct Feature {
  let id: String
  let title: String
  let restrictions: [String]
  let preferences: [ForcedPreference]
  let modelSets: [String]
  /// The first macOS version (major, minor) that has the feature. Apple ships
  /// Apple Intelligence in waves, so a feature the running macOS does not have
  /// is hidden instead of being switched off with keys or model sets the
  /// system ignores. Each value is the newest version any of the feature's
  /// keys needs, from Apple's device-management restrictions reference
  /// (Writing Tools and Siri in 15.1, ChatGPT in 15.2, Notes summaries in
  /// 15.3, Mail smart replies and Safari summaries in 15.4) or, for Spatial
  /// Photos, from the asset set itself, which macOS 15 does not describe.
  var since: (Int, Int) = (15, 1)

  var supported: Bool {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return (os.majorVersion, os.minorVersion) >= since
  }
}

/// A downloadable model set in Apple's asset service.
struct ModelSet {
  let name: String
  let assetType: String
  let title: String
}

enum Catalog {
  static let foundationModels = "com.apple.modelcatalog"
  static let visualModels = "com.apple.MobileAsset.UAF.FM.Visual"
  static let codeModels = "com.apple.MobileAsset.UAF.FM.CodeLM"
  static let cleanUpModels = "com.apple.MobileAsset.UAF.Photos.MagicCleanup"
  static let spatialModels = "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"

  static let modelSets: [ModelSet] = [
    ModelSet(
      name: foundationModels, assetType: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
      title: "Apple Intelligence foundation models"),
    ModelSet(name: visualModels, assetType: visualModels, title: "Image and Genmoji models"),
    ModelSet(name: spatialModels, assetType: spatialModels, title: "Spatial Photos models"),
    ModelSet(name: cleanUpModels, assetType: cleanUpModels, title: "Photos Clean Up models"),
    ModelSet(name: codeModels, assetType: codeModels, title: "Xcode code completion models"),
  ]

  static let features: [Feature] = [
    Feature(
      id: "siri", title: "Siri and Siri AI", restrictions: ["allowAssistant"],
      preferences: [
        ForcedPreference(domain: "com.apple.assistant.support", key: "Assistant Enabled", off: false),
        ForcedPreference(domain: "com.apple.Siri", key: "StatusMenuVisible", off: false),
        ForcedPreference(domain: "com.apple.Siri", key: "VoiceTriggerUserEnabled", off: false),
      ], modelSets: [foundationModels]),
    Feature(
      id: "chatgpt", title: "ChatGPT and other AI extensions",
      restrictions: [
        "allowExternalIntelligenceIntegrations", "allowExternalIntelligenceIntegrationsSignIn",
      ], preferences: [], modelSets: [], since: (15, 2)),
    Feature(
      id: "writing-tools", title: "Writing Tools", restrictions: ["allowWritingTools"],
      preferences: [], modelSets: [foundationModels]),
    Feature(
      id: "genmoji", title: "Genmoji", restrictions: ["allowGenmoji"], preferences: [],
      modelSets: [foundationModels, visualModels]),
    Feature(
      id: "image-playground", title: "Image Playground", restrictions: ["allowImagePlayground"],
      preferences: [], modelSets: [foundationModels, visualModels]),
    Feature(
      id: "mail", title: "Mail summaries and smart replies",
      restrictions: ["allowMailSummary", "allowMailSmartReplies"],
      preferences: [
        ForcedPreference(
          domain: "group.com.apple.mail", key: "DisableAutomaticMessageSummarization", off: true),
        ForcedPreference(domain: "group.com.apple.mail", key: "PersonalizedSmartReplies", off: false),
      ], modelSets: [foundationModels], since: (15, 4)),
    Feature(
      id: "notification-summaries", title: "Notification summaries", restrictions: [],
      preferences: [
        ForcedPreference(domain: "group.com.apple.usernoted", key: "summarize_previews", off: false)
      ], modelSets: [foundationModels], since: (15, 1)),
    Feature(
      id: "messages-summaries", title: "Messages summaries", restrictions: [],
      preferences: [
        ForcedPreference(domain: "com.apple.MobileSMS", key: "messageSummarizationEnabled", off: false)
      ], modelSets: [foundationModels], since: (15, 1)),
    Feature(
      id: "safari-summaries", title: "Safari summaries", restrictions: ["allowSafariSummary"],
      preferences: [], modelSets: [foundationModels], since: (15, 4)),
    Feature(
      id: "notes-summaries", title: "Notes transcription summaries",
      restrictions: ["allowNotesTranscriptionSummary"], preferences: [],
      modelSets: [foundationModels], since: (15, 3)),
    Feature(
      id: "inline-predictions", title: "Inline text predictions", restrictions: [],
      preferences: [
        ForcedPreference(
          domain: ".GlobalPreferences", key: "NSAutomaticInlinePredictionEnabled", off: false)
      ], modelSets: [], since: (15, 1)),
    Feature(
      id: "spatial-photos", title: "Spatial Photos", restrictions: [],
      preferences: [
        ForcedPreference(domain: "com.apple.spatialphotosrelive", key: "LocallyDisabled", off: true)
      ], modelSets: [spatialModels], since: (26, 0)),
    Feature(
      id: "photos-clean-up", title: "Photos Clean Up", restrictions: [], preferences: [],
      modelSets: [cleanUpModels], since: (15, 1)),
    Feature(
      id: "xcode-completion", title: "Xcode predictive code completion", restrictions: [],
      preferences: [], modelSets: [codeModels]),
  ]

  static func feature(_ id: String) -> Feature? { features.first { $0.id == id } }

  static func modelSet(_ name: String) -> ModelSet? { modelSets.first { $0.name == name } }

  /// The features this macOS has. The rest are hidden rather than offered with
  /// keys the system ignores, or model sets it does not describe.
  static var availableFeatures: [Feature] { features.filter(\.supported) }

  /// The model sets this macOS has: those a supported feature still names.
  static var availableModelSets: [ModelSet] {
    modelSets.filter { set in
      availableFeatures.contains { $0.modelSets.contains(set.name) }
    }
  }

  /// The sets to remove: every available set whose features are all being
  /// turned off. A set that a kept feature still needs stays.
  static func setsToRemove(keeping kept: Set<String>) -> [String] {
    availableModelSets.map(\.name).filter { set in
      let users = availableFeatures.filter { $0.modelSets.contains(set) }
      return !users.isEmpty && users.allSatisfy { !kept.contains($0.id) }
    }
  }
}
