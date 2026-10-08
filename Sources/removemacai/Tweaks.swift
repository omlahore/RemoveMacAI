import Foundation

/// A sidebar section of the catalog.
enum TweakGroup: String, CaseIterable, Identifiable {
  case privacy, annoyances, apps, finder, windows, typing

  var id: String { rawValue }

  var title: String {
    switch self {
    case .privacy: return "Privacy"
    case .annoyances: return "Annoyances"
    case .apps: return "Apple Apps"
    case .finder: return "Finder"
    case .windows: return "Dock and Windows"
    case .typing: return "Typing"
    }
  }

  var symbol: String {
    switch self {
    case .privacy: return "hand.raised"
    case .annoyances: return "bell.slash"
    case .apps: return "square.grid.2x2"
    case .finder: return "folder"
    case .windows: return "dock.rectangle"
    case .typing: return "keyboard"
    }
  }

  var summary: String {
    switch self {
    case .privacy: return "Stop your Mac sending analytics, searches and recordings to Apple."
    case .annoyances: return "Turn off the pop-ups, widgets and surprises nobody asked for."
    case .apps: return "Quiet the Apple apps you don't use. macOS won't let anyone delete them."
    case .finder: return "Show what Finder hides and stop the clutter it leaves behind."
    case .windows: return "A faster Dock without the extra icons and animations."
    case .typing: return "Stop macOS rewriting what you type."
    }
  }
}

/// A named starting selection.
enum Preset: String, CaseIterable, Identifiable {
  case recommended, privacy

  var id: String { rawValue }

  var title: String {
    switch self {
    case .recommended: return "Recommended"
    case .privacy: return "Maximum privacy"
    }
  }

  var summary: String {
    switch self {
    case .recommended: return "Apple Intelligence off, no analytics or ads, fewer pop-ups. Nothing you rely on stops working."
    case .privacy: return "Everything in Recommended, plus Game Center and Safari's search suggestions off."
    }
  }
}

/// One setting a tweak changes.
enum Change: Equatable {
  /// A restriction key the profile sets to false.
  case restriction(String)
  /// A preference the profile forces, so it can't be changed back by hand.
  case forced(String, String, PlistValue)
  /// A preference written for the current user.
  case pref(String, String, PlistValue, currentHost: Bool = false)
  /// A launchd agent in the user's session, disabled and unloaded.
  case service(String)
  /// Music's application job, whose label changes when macOS replaces its files.
  case musicLaunches
  /// Dock icons removed by bundle identifier.
  case dockRemove([String])
  /// ~/Library shown in Finder.
  case showLibrary

  var inProfile: Bool {
    switch self {
    case .restriction, .forced: return true
    default: return false
    }
  }

  /// The journal key; two tweaks never change the same thing.
  var key: String {
    switch self {
    case .restriction(let k): return "restriction:\(k)"
    case .forced(let d, let k, _): return "forced:\(d):\(k)"
    case .pref(let d, let k, _, let host): return "pref:\(d):\(k)" + (host ? ":currentHost" : "")
    case .service(let l): return "service:\(l)"
    case .musicLaunches: return "application:com.apple.Music"
    case .dockRemove(let ids): return "dock:" + ids.joined(separator: ",")
    case .showLibrary: return "library"
    }
  }

  /// The equivalent command, shown before anything changes.
  var command: String {
    switch self {
    case .restriction(let k): return "profile: com.apple.applicationaccess \(k) = false"
    case .forced(let d, let k, let v): return "profile: \(d) \(k) = \(v) (locked)"
    case .pref(let d, let k, let v, let host):
      let type: String
      switch v {
      case .bool: type = "-bool"
      case .int: type = "-int"
      case .double: type = "-float"
      case .string: type = "-string"
      }
      let value: String
      if case .string(let s) = v { value = "\"\(s)\"" } else { value = v.description }
      return "defaults\(host ? " -currentHost" : "") write \(d) \"\(k)\" \(type) \(value)"
    case .service(let l): return "launchctl disable gui/$UID/\(l) && launchctl bootout gui/$UID/\(l)"
    case .musicLaunches:
      guard let label = try? MusicLaunch.label() else { return "could not identify Music's application launch entry" }
      return Change.service(label).command
    case .dockRemove(let ids): return "remove from the Dock: " + ids.joined(separator: ", ")
    case .showLibrary: return "chflags nohidden ~/Library"
    }
  }
}

struct Tweak: Identifiable {
  let id: String
  let group: TweakGroup
  let title: String
  let detail: String
  var caveat: String? = nil
  let changes: [Change]
  /// Processes that read the setting only at launch.
  var restart: [String] = []
  var presets: Set<Preset> = []
  /// The first macOS version (major, minor) that has the setting.
  var since: (Int, Int) = (14, 0)

  var inProfile: Bool { changes.contains { $0.inProfile } }

  var supported: Bool {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return (os.majorVersion, os.minorVersion) >= since
  }
}

enum Tweaks {
  static let all: [Tweak] = [
    // MARK: Privacy
    Tweak(
      id: "analytics", group: .privacy, title: "Turn off Mac Analytics",
      detail: "Stops your Mac sending diagnostic and usage data to Apple and to app developers.",
      changes: [.restriction("allowDiagnosticSubmission")], presets: [.recommended, .privacy]),
    Tweak(
      id: "personalized-ads", group: .privacy, title: "Turn off personalized ads",
      detail: "Stops Apple using what you do in its apps to target ads in the App Store, News and Stocks.",
      changes: [.restriction("allowApplePersonalizedAdvertising")], presets: [.recommended, .privacy]),
    Tweak(
      id: "improve-siri", group: .privacy, title: "Turn off Improve Siri and Dictation",
      detail: "Stops Apple storing and reviewing recordings of your Siri and dictation requests.",
      changes: [.forced("com.apple.assistant.support", "Siri Data Sharing Opt-In Status", .int(2))],
      presets: [.recommended, .privacy]),
    Tweak(
      id: "improve-search", group: .privacy, title: "Turn off Improve Search",
      detail: "Stops Apple keeping your Spotlight, Safari and Look Up searches to improve search.",
      changes: [.forced("com.apple.assistant.support", "Search Queries Data Sharing Status", .int(2))],
      presets: [.recommended, .privacy]),
    Tweak(
      id: "spotlight-web", group: .privacy, title: "Turn off Spotlight internet results",
      detail: "Keeps Spotlight searches on your Mac instead of sending them to Apple for web suggestions.",
      changes: [.restriction("allowSpotlightInternetResults")], presets: [.recommended, .privacy]),
    Tweak(
      id: "lookup-suggestions", group: .privacy, title: "Turn off Look Up suggestions",
      detail: "Stops Look Up sending the words you select to Apple for web results.",
      changes: [.forced("com.apple.lookup.shared", "LookupSuggestionsDisabled", .bool(true))],
      presets: [.recommended, .privacy]),
    Tweak(
      id: "safari-suggestions", group: .privacy, title: "Turn off Safari search suggestions",
      detail: "Stops Safari sending what you type in the address bar to your search engine and to Apple.",
      caveat: "The address bar no longer suggests searches as you type.",
      changes: [
        .forced("com.apple.Safari", "UniversalSearchEnabled", .bool(false)),
        .forced("com.apple.Safari", "SuppressSearchSuggestions", .bool(true)),
      ], presets: [.privacy]),
    Tweak(
      id: "game-center", group: .privacy, title: "Turn off Game Center",
      detail: "Turns Game Center off, with its sign-in prompts, friend requests and notifications.",
      caveat: "Games that need Game Center to save progress or play online lose that.",
      changes: [.restriction("allowGameCenter")], presets: [.privacy]),

    // MARK: Annoyances
    Tweak(
      id: "click-to-desktop", group: .annoyances, title: "Stop clicks on the wallpaper hiding windows",
      detail: "Stops every window sliding away when you click the wallpaper by mistake.",
      changes: [.pref("com.apple.WindowManager", "EnableStandardClickToShowDesktop", .bool(false))],
      presets: [.recommended]),
    Tweak(
      id: "desktop-widgets", group: .annoyances, title: "Hide desktop widgets",
      detail: "Hides widgets on the desktop, including in Stage Manager.",
      changes: [
        .pref("com.apple.WindowManager", "StandardHideWidgets", .bool(true)),
        .pref("com.apple.WindowManager", "StageManagerHideWidgets", .bool(true)),
      ]),
    Tweak(
      id: "media-keys", group: .annoyances, title: "Stop the play key opening Music",
      detail: "Stops the play key opening Music when nothing else is playing.",
      caveat: "The play key no longer starts Music itself.",
      changes: [.service("com.apple.rcd")], presets: [.recommended]),
    Tweak(
      id: "music-launches", group: .annoyances, title: "Block Music launches, including from AirPods",
      detail: "Disables Music's application launch entry, so an AirPod press no longer opens it. No background helper or configuration profile is installed.",
      caveat: "Closes Music and blocks manual launches too. Reapply after a macOS update replaces Music's files.",
      changes: [.musicLaunches]),
    Tweak(
      id: "iphone-mirroring", group: .annoyances, title: "Turn off iPhone Mirroring",
      detail: "Turns iPhone Mirroring off, so the app and its prompts go away.",
      changes: [.restriction("allowiPhoneMirroring")], since: (15, 0)),

    // MARK: Apple apps
    Tweak(
      id: "music-classic", group: .apps, title: "Turn off Apple Music in the Music app",
      detail: "Turns the Music app back into a plain player for your own library, without the store and subscription prompts.",
      caveat: "Apple Music subscribers lose streaming.",
      changes: [.restriction("allowMusicService")]),
    Tweak(
      id: "book-store", group: .apps, title: "Turn off the Book Store",
      detail: "Removes the store from the Books app and keeps your own books.",
      changes: [.restriction("allowBookstore")], since: (15, 0)),
    Tweak(
      id: "dock-apple-apps", group: .apps, title: "Remove unused Apple apps from the Dock",
      detail: "Removes News, TV, Music, Podcasts, Books, Freeform, Maps and Stocks from the Dock. The apps stay installed.",
      changes: [.dockRemove([
        "com.apple.news", "com.apple.TV", "com.apple.Music", "com.apple.podcasts", "com.apple.iBooksX",
        "com.apple.freeform", "com.apple.Maps", "com.apple.stocks",
      ])], restart: ["Dock"]),

    // MARK: Finder
    Tweak(
      id: "file-extensions", group: .finder, title: "Show file extensions",
      detail: "Shows the full name of every file, so a file pretending to be a document is easier to spot.",
      changes: [.pref(Prefs.global, "AppleShowAllExtensions", .bool(true))], restart: ["Finder"],
      presets: [.recommended, .privacy]),
    Tweak(
      id: "hidden-files", group: .finder, title: "Show hidden files",
      detail: "Shows the files macOS hides, such as .gitignore and .zshrc. Press Command-Shift-Period to toggle it too.",
      changes: [.pref("com.apple.finder", "AppleShowAllFiles", .bool(true))], restart: ["Finder"]),
    Tweak(
      id: "path-bar", group: .finder, title: "Show the path bar",
      detail: "Shows where the current folder is at the bottom of every Finder window.",
      changes: [.pref("com.apple.finder", "ShowPathbar", .bool(true))], restart: ["Finder"],
      presets: [.recommended]),
    Tweak(
      id: "status-bar", group: .finder, title: "Show the status bar",
      detail: "Shows the number of items and the free space at the bottom of Finder windows.",
      changes: [.pref("com.apple.finder", "ShowStatusBar", .bool(true))], restart: ["Finder"]),
    Tweak(
      id: "folders-first", group: .finder, title: "Keep folders above files",
      detail: "Keeps folders above files when sorting by name.",
      changes: [.pref("com.apple.finder", "_FXSortFoldersFirst", .bool(true))], restart: ["Finder"],
      presets: [.recommended]),
    Tweak(
      id: "search-this-folder", group: .finder, title: "Search the current folder",
      detail: "Makes Finder search the folder you're in, not the whole Mac.",
      changes: [.pref("com.apple.finder", "FXDefaultSearchScope", .string("SCcf"))], restart: ["Finder"]),
    Tweak(
      id: "extension-warning", group: .finder, title: "Skip the extension change warning",
      detail: "Stops Finder asking for confirmation each time you change a file's extension.",
      changes: [.pref("com.apple.finder", "FXEnableExtensionChangeWarning", .bool(false))], restart: ["Finder"]),
    Tweak(
      id: "path-in-title", group: .finder, title: "Show the full path in the title bar",
      detail: "Shows the full folder path at the top of Finder windows.",
      changes: [.pref("com.apple.finder", "_FXShowPosixPathInTitle", .bool(true))], restart: ["Finder"]),
    Tweak(
      id: "network-ds-store", group: .finder, title: "Stop .DS_Store files on network drives",
      detail: "Stops Finder leaving .DS_Store files in shared folders on other computers.",
      changes: [.pref("com.apple.desktopservices", "DSDontWriteNetworkStores", .bool(true))],
      presets: [.recommended]),
    Tweak(
      id: "trash-30-days", group: .finder, title: "Empty the Trash after 30 days",
      detail: "Deletes items that have been in the Trash for 30 days, so it stops filling the disk.",
      changes: [.pref("com.apple.finder", "FXRemoveOldTrashItems", .bool(true))], restart: ["Finder"]),
    Tweak(
      id: "save-locally", group: .finder, title: "Save new documents on this Mac",
      detail: "Makes Save dialogs start on your Mac instead of iCloud Drive.",
      changes: [.pref(Prefs.global, "NSDocumentSaveNewDocumentsToCloud", .bool(false))]),
    Tweak(
      id: "expanded-save", group: .finder, title: "Expand Save dialogs",
      detail: "Opens Save dialogs with the full folder browser instead of the small version.",
      changes: [.pref(Prefs.global, "NSNavPanelExpandedStateForSaveMode", .bool(true))]),
    Tweak(
      id: "show-library", group: .finder, title: "Show the Library folder",
      detail: "Shows the hidden Library folder in your home folder.",
      changes: [.showLibrary]),

    // MARK: Dock and windows
    Tweak(
      id: "dock-recents", group: .windows, title: "Hide recent apps in the Dock",
      detail: "Stops the Dock adding apps you opened recently.",
      changes: [.pref("com.apple.dock", "show-recents", .bool(false))], restart: ["Dock"],
      presets: [.recommended]),
    Tweak(
      id: "dock-delay", group: .windows, title: "Remove the Dock auto-hide delay",
      detail: "Shows a hidden Dock straight away instead of after half a second.",
      changes: [.pref("com.apple.dock", "autohide-delay", .double(0))], restart: ["Dock"]),
    Tweak(
      id: "dock-bounce", group: .windows, title: "Stop Dock icons bouncing",
      detail: "Stops Dock icons bouncing while apps open.",
      changes: [.pref("com.apple.dock", "launchanim", .bool(false))], restart: ["Dock"]),
    Tweak(
      id: "minimize-to-app", group: .windows, title: "Minimize windows into their app icon",
      detail: "Keeps minimized windows inside their app's icon instead of filling the Dock.",
      changes: [.pref("com.apple.dock", "minimize-to-application", .bool(true))], restart: ["Dock"]),
    Tweak(
      id: "window-animations", group: .windows, title: "Turn off window opening animations",
      detail: "Opens new windows instantly instead of zooming them in.",
      changes: [.pref(Prefs.global, "NSAutomaticWindowAnimationsEnabled", .bool(false))]),
    Tweak(
      id: "tile-margins", group: .windows, title: "Remove gaps between tiled windows",
      detail: "Removes the margins around windows you tile to the sides of the screen.",
      changes: [.pref("com.apple.WindowManager", "EnableTiledWindowMargins", .bool(false))], since: (15, 0)),
    Tweak(
      id: "screenshot-shadow", group: .windows, title: "Remove shadows from window screenshots",
      detail: "Takes window screenshots without the large drop shadow around them.",
      changes: [.pref("com.apple.screencapture", "disable-shadow", .bool(true))], restart: ["SystemUIServer"]),

    // MARK: Typing
    Tweak(
      id: "autocorrect", group: .typing, title: "Turn off autocorrect",
      detail: "Stops macOS correcting words as you type.",
      changes: [.pref(Prefs.global, "NSAutomaticSpellingCorrectionEnabled", .bool(false))]),
    Tweak(
      id: "smart-punctuation", group: .typing, title: "Turn off smart quotes and dashes",
      detail: "Keeps straight quotes and double hyphens as you typed them, which code and terminals need.",
      changes: [
        .pref(Prefs.global, "NSAutomaticQuoteSubstitutionEnabled", .bool(false)),
        .pref(Prefs.global, "NSAutomaticDashSubstitutionEnabled", .bool(false)),
      ]),
    Tweak(
      id: "double-space-period", group: .typing, title: "Turn off period on double space",
      detail: "Stops two spaces turning into a period.",
      changes: [.pref(Prefs.global, "NSAutomaticPeriodSubstitutionEnabled", .bool(false))]),
    Tweak(
      id: "auto-capitalize", group: .typing, title: "Turn off automatic capitals",
      detail: "Stops macOS capitalizing the first word of each sentence.",
      changes: [.pref(Prefs.global, "NSAutomaticCapitalizationEnabled", .bool(false))]),
    Tweak(
      id: "key-repeat", group: .typing, title: "Repeat held keys instead of showing accents",
      detail: "Repeats a key while you hold it, instead of opening the accent menu.",
      caveat: "Type accents with Option shortcuts or the Character Viewer instead.",
      changes: [.pref(Prefs.global, "ApplePressAndHoldEnabled", .bool(false))]),
  ]

  static func tweak(_ id: String) -> Tweak? { all.first { $0.id == id } }

  /// Maximum privacy builds on Recommended.
  static func preset(_ preset: Preset) -> [Tweak] {
    let names: Set<Preset> = preset == .privacy ? [.recommended, .privacy] : [preset]
    return all.filter { !$0.presets.isDisjoint(with: names) && $0.supported }
  }
}
