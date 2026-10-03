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
  static let fmOverrides = "com.apple.MobileAsset.UAF.FM.Overrides"
  static let summarization = "com.apple.summarizationkit"
  static let siriVoice = "com.apple.siri.tts"
  static let siriVoiceTraining = "com.apple.siri.ttstraining"
  static let siriUnderstanding = "com.apple.siri.understanding"
  static let siriUnderstandingOverrides = "com.apple.siri.understanding.nl.overrides"
  static let siriListening = "com.apple.siri.asr.hammer"
  static let siriDialog = "com.apple.siri.dialog"
  static let siriFindMy = "com.apple.siri.findmy"
  static let siriPerception = "com.apple.voiceassistant.perception"
  static let planner = "com.apple.if.planner"
  static let plannerOverrides = "com.apple.if.planner.overrides"
  static let speechRecognition = "com.apple.speech.automaticspeechrecognition"
  static let shortcutsModels = "com.apple.MobileAsset.UAF.Shortcuts.Generator"
  static let handwritingModels = "com.apple.MobileAsset.UAF.Handwriting.Synthesis"
  static let safariAssistant = "com.apple.parsec.sba"

  static let siriSets = [
    siriVoice, siriVoiceTraining, siriUnderstanding, siriUnderstandingOverrides, siriListening,
    siriDialog, siriFindMy, siriPerception, planner, plannerOverrides,
  ]

  static let modelSets: [ModelSet] = [
    ModelSet(
      name: foundationModels, assetType: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
      title: "Apple Intelligence foundation models"),
    ModelSet(name: visualModels, assetType: visualModels, title: "Image and Genmoji models"),
    ModelSet(name: spatialModels, assetType: spatialModels, title: "Spatial Photos models"),
    ModelSet(name: cleanUpModels, assetType: cleanUpModels, title: "Photos Clean Up models"),
    ModelSet(name: codeModels, assetType: codeModels, title: "Xcode code completion models"),
    ModelSet(name: fmOverrides, assetType: fmOverrides, title: "Foundation model safety settings"),
    ModelSet(
      name: summarization, assetType: "com.apple.MobileAsset.UAF.SummarizationKitConfiguration",
      title: "Summaries configuration"),
    ModelSet(name: siriVoice, assetType: "com.apple.MobileAsset.UAF.Siri.TextToSpeech", title: "Siri voices"),
    ModelSet(
      name: siriVoiceTraining, assetType: "com.apple.MobileAsset.UAF.Siri.TTSDeviceTraining",
      title: "Siri voice training"),
    ModelSet(
      name: siriUnderstanding, assetType: "com.apple.MobileAsset.UAF.Siri.Understanding",
      title: "Siri understanding models"),
    ModelSet(
      name: siriUnderstandingOverrides, assetType: "com.apple.MobileAsset.UAF.Siri.UnderstandingNLOverrides",
      title: "Siri understanding overrides"),
    ModelSet(
      name: siriListening, assetType: "com.apple.MobileAsset.UAF.Siri.UnderstandingASRHammer",
      title: "Siri listening models"),
    ModelSet(name: siriDialog, assetType: "com.apple.MobileAsset.UAF.Siri.DialogAssets", title: "Siri dialog"),
    ModelSet(
      name: siriFindMy, assetType: "com.apple.MobileAsset.UAF.Siri.FindMyConfigurationFiles",
      title: "Siri Find My"),
    ModelSet(
      name: siriPerception, assetType: "com.apple.MobileAsset.UAF.VoiceAssistant",
      title: "Voice assistant perception"),
    ModelSet(name: planner, assetType: "com.apple.MobileAsset.UAF.IF.Planner", title: "Siri AI planner"),
    ModelSet(
      name: plannerOverrides, assetType: "com.apple.MobileAsset.UAF.IF.PlannerOverrides",
      title: "Siri AI planner overrides"),
    ModelSet(
      name: speechRecognition, assetType: "com.apple.MobileAsset.UAF.Speech.AutomaticSpeechRecognition",
      title: "Speech recognition models"),
    ModelSet(name: shortcutsModels, assetType: shortcutsModels, title: "Shortcuts generator models"),
    ModelSet(name: handwritingModels, assetType: handwritingModels, title: "Handwriting models"),
    ModelSet(
      name: safariAssistant, assetType: "com.apple.MobileAsset.UAF.SafariBrowsingAssistant",
      title: "Safari browsing assistant"),
  ]

  static let features: [Feature] = [
    Feature(
      id: "siri", title: "Siri and Siri AI", restrictions: ["allowAssistant"],
      preferences: [
        ForcedPreference(domain: "com.apple.assistant.support", key: "Assistant Enabled", off: false),
        ForcedPreference(domain: "com.apple.Siri", key: "StatusMenuVisible", off: false),
        ForcedPreference(domain: "com.apple.Siri", key: "VoiceTriggerUserEnabled", off: false),
      ], modelSets: [foundationModels, fmOverrides] + siriSets),
    Feature(
      id: "dictation", title: "Dictation and speech recognition", restrictions: ["allowDictation"],
      preferences: [
        ForcedPreference(domain: "com.apple.HIToolbox", key: "AppleDictationAutoEnable", off: false)
      ], modelSets: [speechRecognition, siriUnderstanding]),
    Feature(
      id: "intelligence-report", title: "Apple Intelligence Report",
      restrictions: ["allowAppleIntelligenceReport"], preferences: [], modelSets: []),
    Feature(
      id: "chatgpt", title: "ChatGPT and other AI extensions",
      restrictions: [
        "allowExternalIntelligenceIntegrations", "allowExternalIntelligenceIntegrationsSignIn",
      ], preferences: [], modelSets: []),
    Feature(
      id: "writing-tools", title: "Writing Tools", restrictions: ["allowWritingTools"],
      preferences: [], modelSets: [foundationModels, fmOverrides]),
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
      ], modelSets: [foundationModels, summarization]),
    Feature(
      id: "notification-summaries", title: "Notification summaries", restrictions: [],
      preferences: [
        ForcedPreference(domain: "group.com.apple.usernoted", key: "summarize_previews", off: false)
      ], modelSets: [foundationModels, summarization]),
    Feature(
      id: "messages-summaries", title: "Messages summaries", restrictions: [],
      preferences: [
        ForcedPreference(domain: "com.apple.MobileSMS", key: "messageSummarizationEnabled", off: false)
      ], modelSets: [foundationModels]),
    Feature(
      id: "safari-summaries", title: "Safari summaries and browsing assistant",
      restrictions: ["allowSafariSummary"], preferences: [], modelSets: [foundationModels, safariAssistant]),
    Feature(
      id: "notes-summaries", title: "Notes transcription and summaries",
      restrictions: ["allowNotesTranscription", "allowNotesTranscriptionSummary"], preferences: [],
      modelSets: [foundationModels, speechRecognition]),
    Feature(
      id: "inline-predictions", title: "Inline text predictions", restrictions: [],
      preferences: [
        ForcedPreference(
          domain: ".GlobalPreferences", key: "NSAutomaticInlinePredictionEnabled", off: false)
      ], modelSets: []),
    Feature(
      id: "spatial-photos", title: "Spatial Photos", restrictions: [],
      preferences: [
        ForcedPreference(domain: "com.apple.spatialphotosrelive", key: "LocallyDisabled", off: true)
      ], modelSets: [spatialModels]),
    Feature(
      id: "photos-clean-up", title: "Photos Clean Up", restrictions: [], preferences: [],
      modelSets: [cleanUpModels]),
    Feature(
      id: "xcode-completion", title: "Xcode predictive code completion", restrictions: [],
      preferences: [
        ForcedPreference(domain: "com.apple.dt.Xcode", key: "DVTEnableOnDeviceCodePredictions", off: false),
        ForcedPreference(domain: "com.apple.dt.Xcode", key: "DVTTextEnablePredictiveCompletion", off: false),
      ], modelSets: [codeModels]),
    Feature(
      id: "shortcuts-ai", title: "Shortcuts AI generation", restrictions: [], preferences: [],
      modelSets: [shortcutsModels]),
    Feature(
      id: "handwriting", title: "Handwriting synthesis (Math Notes)", restrictions: [], preferences: [],
      modelSets: [handwritingModels]),
  ]

  static func feature(_ id: String) -> Feature? { features.first { $0.id == id } }

  static func modelSet(_ name: String) -> ModelSet? { modelSets.first { $0.name == name } }

  /// The sets to remove: every set whose features are all being turned off.
  /// A set that a kept feature still needs stays.
  static func setsToRemove(keeping kept: Set<String>) -> [String] {
    modelSets.map(\.name).filter { set in
      let users = features.filter { $0.modelSets.contains(set) }
      return !users.isEmpty && users.allSatisfy { !kept.contains($0.id) }
    }
  }
}
