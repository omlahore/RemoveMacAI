import Foundation

/// Checks the parts that must never go wrong, runnable without Xcode:
/// `removemacai selftest`. Touches nothing on the system.
func selfTest() -> Bool {
  var failed = 0
  func check(_ ok: Bool, _ what: String) {
    print((ok ? Term.green("pass ") : Term.red("FAIL ")) + what)
    if !ok { failed += 1 }
  }
  func throwsFailure(_ body: () throws -> Void) -> Bool {
    do { try body() } catch is Failure { return true } catch { return false }
    return false
  }

  check(Set(Catalog.setsToRemove(keeping: [])) == Set(Catalog.modelSets.map(\.name)),
    "off removes every model set")
  let keptWriting = Catalog.setsToRemove(keeping: ["writing-tools"])
  check(!keptWriting.contains(Catalog.foundationModels) && keptWriting.contains(Catalog.spatialModels),
    "a kept feature keeps the models it needs, and only those")
  check(Catalog.setsToRemove(keeping: Set(Catalog.features.map(\.id))).isEmpty,
    "keeping everything removes nothing")
  check(Catalog.features.allSatisfy { $0.modelSets.allSatisfy { Catalog.modelSet($0) != nil } },
    "every model set a feature names is in the catalog")
  check(Set(Catalog.features.map(\.id)).count == Catalog.features.count, "feature names are unique")
  check(throwsFailure { try Models.remove([]) }, "an empty removal is refused before anything is sent")
  check(throwsFailure { try Models.remove(["com.apple.something.else"]) }, "an unknown set is refused")
  let all = Catalog.modelSets.map(\.name)
  let types = Dictionary(uniqueKeysWithValues: Catalog.modelSets.map { ($0.name, $0.assetType) })
  let split = try? Models.matching(all) { $0 == Catalog.spatialModels ? "com.apple.something.else" : types[$0] }
  check(split?.matched == all.filter { $0 != Catalog.spatialModels } && split?.skipped.map { $0.0 } == [Catalog.spatialModels],
    "a set this macOS describes differently is left alone and the rest still go")
  let missing = try? Models.matching(all) { _ in nil }
  check(missing?.matched.isEmpty == true && missing?.skipped.count == all.count,
    "sets this macOS does not have are left alone")
  let parsed = Models.parseInventory(["SystemAssets": [
    ["isPresentOnDevice": true, "metadata": ["AssetType": "a", "_UnarchivedSize": 100]],
    ["isPresentOnDevice": true, "metadata": ["AssetType": "a", "com.apple.UnifiedAssetFramework.UnarchivedSize": "50"]],
    ["isPresentOnDevice": false, "metadata": ["AssetType": "a", "_UnarchivedSize": 999]],
    ["isPresentOnDevice": true, "metadata": ["AssetType": "b"]],
  ]])
  check(parsed == ["a": 150, "b": 0], "the inventory counts only assets that are on disk")

  let sampleSets = ["first", "second"]
  check(Models.total(sampleSets, read: { ["first": Int64(5), "second": 7][$0] }) == 12,
    "known model sizes are added")
  check(Models.total(sampleSets, read: { _ in 0 }) == 0,
    "known zero sizes stay zero")
  check(Models.total(sampleSets, read: { _ in nil }) == nil,
    "failed size queries do not become zero")
  check(Models.total(sampleSets, read: { $0 == "first" ? 0 : nil }) == nil,
    "one unknown size keeps a zero total unknown")
  check(Models.total(sampleSets, read: { $0 == "first" ? 5 : nil }) == nil,
    "one unknown size does not produce a partial total")
  var emptyReads = 0
  check(Models.total([], read: { _ in emptyReads += 1; return nil }) == 0 && emptyReads == 0,
    "an empty total needs no asset queries")

  check(Settings.modelState(sampleSets, read: { _ in nil }) == .unknown,
    "unavailable model sizes produce an unknown feature state")
  check(Settings.modelState(sampleSets, read: { $0 == "first" ? 0 : nil }) == .unknown,
    "zero and unknown sizes do not turn a feature off")
  check(Settings.modelState(sampleSets, read: { $0 == "first" ? nil : 5 }) == .on,
    "a known downloaded model keeps a feature on")
  check(Settings.modelState(sampleSets, read: { _ in 0 }) == .off,
    "a model-only feature is off when every size is zero")
  check(!FeatureState.unknown.isOff && !FeatureState.on.isOff
    && FeatureState.off.isOff && FeatureState.lockedOff.isOff,
    "unknown feature states do not count as off")
  check(Commands.modelSize(nil).contains("unknown") && Commands.modelSize(0).contains("none")
    && Commands.modelSize(1024).contains(Term.size(1024)),
    "model size labels distinguish unknown, empty and downloaded")

  // Every removal dependency below is fake; no asset service is contacted.
  func simulatedRemoval(before: Int64?, after: Int64?, failures: [(String, String)] = [],
    waitExpires: Bool = false) throws -> ModelRemovalResult
  {
    try Commands.removeModels(sampleSets, before: before, remove: { _ in failures },
      total: { _ in after }, wait: { condition in
        let zero = condition()
        return !waitExpires && zero
      })
  }
  do {
    let unknownBefore = try simulatedRemoval(before: nil, after: 0)
    check(unknownBefore.complete && unknownBefore.deletedBytes == nil,
      "removal can be verified without inventing the initial size")
    let unknownAfter = try simulatedRemoval(before: 100, after: nil)
    check(!unknownAfter.complete && unknownAfter.after == nil && unknownAfter.deletedBytes == nil,
      "failed verification does not claim removal or freed space")
    let complete = try simulatedRemoval(before: 100, after: 0)
    check(complete.complete && complete.deletedBytes == 100,
      "verified zero reports the measured removal")

    var verificationReads = 0
    let transient = try Commands.removeModels(sampleSets, before: 100, remove: { _ in [] },
      total: { _ in verificationReads += 1; return verificationReads == 1 ? nil : 0 },
      wait: { condition in
        if condition() { return true }
        return condition()
      })
    check(transient.complete && transient.deletedBytes == 100 && verificationReads == 2,
      "verification waits through an unknown reading and keeps the final snapshot")

    let partial = try simulatedRemoval(before: 100, after: 40,
      failures: [("second", "reset rejected")])
    check(!partial.complete && partial.deletedBytes == 60 && partial.failures.count == 1,
      "partial reset failures preserve measured progress without claiming success")
    for reason in ["reset rejected", "no answer in 120 seconds"] {
      let resetFailure = try simulatedRemoval(before: 100, after: 0, failures: [("second", reason)])
      check(!resetFailure.complete && resetFailure.verified,
        "a reset failure stays incomplete after zero is observed: \(reason)")
    }
    let timedOut = try simulatedRemoval(before: 100, after: 40, waitExpires: true)
    check(!timedOut.complete && !timedOut.verified && timedOut.deletedBytes == 60,
      "verification timeout reports incomplete removal with known progress")
    let unverifiedZero = try simulatedRemoval(before: 100, after: 0, waitExpires: true)
    check(!unverifiedZero.complete && !unverifiedZero.verified,
      "a failed wait cannot become a successful removal")

    for (sets, before) in [([], nil), (sampleSets, Int64(0))] as [([String], Int64?)] {
      var calls = 0
      let skipped = try Commands.removeModels(sets, before: before,
        remove: { _ in calls += 1; return [] }, total: { _ in calls += 1; return nil },
        wait: { _ in calls += 1; return false })
      check(skipped.complete && skipped.after == 0 && calls == 0,
        "empty selections and known zero sizes need no removal or verification")
    }
    var readsAfterThrow = 0
    check(throwsFailure {
      _ = try Commands.removeModels(sampleSets, before: 100,
        remove: { _ in throw Failure("fake reset failure") },
        total: { _ in readsAfterThrow += 1; return 0 },
        wait: { _ in readsAfterThrow += 1; return true })
    } && readsAfterThrow == 0, "throwing resets propagate before verification")
  } catch {
    check(false, "model removal reporting works with fake dependencies: \(error)")
  }

  do {
    let plist = try PropertyListSerialization.propertyList(from: Profile.data(Profile.Contents(ai: [], tweaks: [])), format: nil)
      as! [String: Any]
    let payloads = plist["PayloadContent"] as! [[String: Any]]
    let restrictions = payloads.first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }!
    check(restrictions["allowWritingTools"] as? Bool == false && restrictions["allowAssistant"] as? Bool == false,
      "the profile turns Writing Tools and Siri off")
    let blocks = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".com.apple.MobileAsset") == true }!
    let content = (blocks["PayloadContent"] as! [String: Any])["com.apple.MobileAsset"] as! [String: Any]
    let settings = ((content["Forced"] as! [[String: Any]])[0]["mcx_preference_settings"]) as! [String: String]
    check(settings.count == Catalog.modelSets.count && settings.values.allSatisfy { $0.hasPrefix("https://127.0.0.1:9/") },
      "the profile blocks downloads for every removed set")
    let uuids = payloads.compactMap { $0["PayloadUUID"] as? String } + [plist["PayloadUUID"] as! String]
    check(Set(uuids).count == uuids.count && Profile.uuid("a") == Profile.uuid("a"),
      "payload UUIDs are unique and stable")

    let keep = try PropertyListSerialization.propertyList(from: Profile.data(Profile.Contents(ai: ["writing-tools"], tweaks: [])), format: nil)
      as! [String: Any]
    let kr = (keep["PayloadContent"] as! [[String: Any]]).first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }!
    check(kr["allowWritingTools"] == nil && kr["allowGenmoji"] as? Bool == false, "a kept feature is left alone")
  } catch {
    check(false, "the profile builds: \(error)")
  }
  // The debloater catalog.
  check(Set(Tweaks.all.map(\.id)).count == Tweaks.all.count, "tweak names are unique")
  let changeKeys = Tweaks.all.flatMap { $0.changes.map(\.key) }
  check(Set(changeKeys).count == changeKeys.count, "no two tweaks change the same setting")
  check(Tweaks.all.allSatisfy { !$0.changes.isEmpty && ($0.changes.allSatisfy(\.inProfile) || !$0.inProfile) },
    "a tweak is either all profile or all local")
  // Restriction keys Apple only accepts from an MDM server; one of these
  // makes macOS reject the whole profile (device-management Release-v27.0).
  let mdmOnly: Set<String> = [
    "allowedExternalIntelligenceWorkspaceIDs", "allowRosettaUsageAwareness", "allowSafariHistoryClearing",
    "allowSafariPrivateBrowsing", "forceBypassScreenCaptureAlert",
  ]
  let profileKeys = Tweaks.all.flatMap(\.changes).compactMap { c -> String? in
    if case .restriction(let k) = c { return k } else { return nil }
  } + Catalog.features.flatMap(\.restrictions)
  check(mdmOnly.isDisjoint(with: profileKeys), "the profile uses no key that needs an MDM server")
  check(Set(Tweaks.preset(.recommended).map(\.id)).isSubset(of: Set(Tweaks.preset(.privacy).map(\.id))),
    "maximum privacy includes everything in recommended")
  check(Set(Tweaks.all.map(\.id)).isDisjoint(with: Set(Catalog.features.map(\.id))),
    "tweak names don't clash with Apple Intelligence feature names")
  check(PlistValue.bool(true).matches(1 as NSNumber) && PlistValue.bool(false).matches(0 as NSNumber)
    && !PlistValue.bool(true).matches(0 as NSNumber) && PlistValue.int(2).matches(2 as NSNumber)
    && PlistValue.double(0).matches(0 as NSNumber) && !PlistValue.string("SCcf").matches(nil),
    "stored values match whether they were written as bools or numbers")
  check(PlistValue(kCFBooleanTrue) == .bool(true) && PlistValue(3 as NSNumber) == .int(3)
    && PlistValue(0.5 as NSNumber) == .double(0.5) && PlistValue("a" as NSString) == .string("a"),
    "stored values keep their types")
  check(Change.pref("com.apple.dock", "autohide-delay", .double(0)).command
    == "defaults write com.apple.dock \"autohide-delay\" -float 0.0", "commands are shown as defaults would take them")

  do {
    let contents = Profile.Contents(ai: nil, tweaks: ["analytics", "lookup-suggestions"])
    let plist = try PropertyListSerialization.propertyList(from: Profile.data(contents), format: nil) as! [String: Any]
    let payloads = plist["PayloadContent"] as! [[String: Any]]
    let restrictions = payloads.first { $0["PayloadType"] as? String == "com.apple.applicationaccess" }
    check(restrictions?["allowDiagnosticSubmission"] as? Bool == false && restrictions?["allowWritingTools"] == nil,
      "a tweak-only profile restricts the tweaks and leaves Apple Intelligence alone")
    check(!payloads.contains { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".com.apple.MobileAsset") == true },
      "a tweak-only profile blocks no model downloads")
    let marker = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".preferences.\(Profile.identifier)") == true }
    let markerSettings = ((marker?["PayloadContent"] as? [String: Any])?[Profile.identifier] as? [String: Any])
      .flatMap { ($0["Forced"] as? [[String: Any]])?.first?["mcx_preference_settings"] as? [String: Any] }
    check(markerSettings?["ai"] as? Bool == false && markerSettings?["tweaks"] as? String == "analytics,lookup-suggestions",
      "the profile records which tweaks it holds")
    let lookup = payloads.first { ($0["PayloadIdentifier"] as? String)?.hasSuffix(".com.apple.lookup.shared") == true }
    check(lookup != nil, "forced tweak preferences are in the profile")
  } catch {
    check(false, "the tweak profile builds: \(error)")
  }

  check(Storage.uniqueName("a.app", in: "/nonexistent-folder") == "a.app", "trash names stay as they are when free")
  let script = BackgroundItem(label: "com.example.sync", plist: "", program: "/bin/bash",
    arguments: ["/bin/bash", "/Users/x/bin/sync.sh"], system: false)
  let helper = BackgroundItem(label: "dev.orbstack.OrbStack.privhelper", plist: "",
    program: "/Library/PrivilegedHelperTools/dev.orbstack.OrbStack.privhelper", system: true)
  check(script.owner == "sync.sh" && helper.owner == "OrbStack", "background items are named after what they run")

  let ranAll = Shell.run("/bin/sh", ["-c", Shell.adminScript(["false", "echo second"])])
  check(!ranAll.ok && ranAll.output.contains("second"), "one failed administrator step doesn't skip the rest")
  let exited = Shell.run("/bin/sh", ["-c", Shell.adminScript(["exit 3", "echo after-exit"])])
  check(!exited.ok && exited.output.contains("after-exit"), "a step that exits doesn't stop the rest")
  check(Shell.run("/bin/sh", ["-c", Shell.adminScript(["true", "true"])]).ok, "administrator steps succeed together")
  check(Term.pad("abc", 5) == "abc  " && Term.pad("abcdef", 5) == "abcdef ", "columns never run together")
  check(Storage.isAppleCache("/x/com.apple.Safari") && Storage.isAppleCache("/x/CloudKit")
    && Storage.isAppleCache("/x/GeoServices") && !Storage.isAppleCache("/x/Homebrew")
    && !Storage.isAppleCache("/x/com.google.Chrome"), "macOS caches without the com.apple. prefix are left alone")
  check(Storage.soundLibraryUsers(["com.apple.finder": "Finder", "com.example.missing": "Missing"]) == ["Finder"],
    "apps that share the sound library are found by bundle identifier")
  let updater = BackgroundItem(label: "com.google.GoogleUpdater.wake", plist: "",
    program: "/Users/x/Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app/Contents/MacOS/GoogleUpdater",
    system: false)
  check(updater.isUpdater && updater.warning == nil && !helper.isUpdater && helper.warning != nil,
    "helpers that aren't updaters carry a warning")
  let vpn = BackgroundItem(label: "com.example.vpn", plist: "", program: "/Library/Example Updates/vpnd",
    arguments: ["/Library/Example Updates/vpnd", "--check-updates"], system: true)
  check(!vpn.isUpdater && vpn.warning != nil, "an unrelated mention of updates keeps the warning")
  MainActor.assumeIsolated {
    let model = AppModel()
    model.modelBytes = ["first": 5]
    check(model.modelBytes(["first"]) == 5 && model.modelBytes(["first", "second"]) == nil,
      "the review sheet shows a model size only when every set has a reading")
  }
  // The journal, in a temporary folder instead of the real one.
  let realFolder = Engine.folder
  let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("removemacai-selftest-\(UUID().uuidString)")
  try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  Engine.folder = scratch
  for _ in 0..<2 {
    try? Data("garbage".utf8).write(to: Engine.journalURL)
    _ = Engine.loadJournal()
  }
  let kept = (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
  check(kept.filter { $0.hasPrefix("journal-unreadable-") }.count == 2 && Engine.journalBlocked == nil,
    "unreadable journals are each kept aside under their own name")
  if getuid() != 0 {
    try? Data("garbage".utf8).write(to: Engine.journalURL)
    try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: scratch.path)
    _ = Engine.loadJournal()
    Engine.save(Engine.Journal())
    check(Engine.journalBlocked != nil && (try? Data(contentsOf: Engine.journalURL)) == Data("garbage".utf8)
      && Engine.runLocal(Plan()) == [Engine.journalBlocked!],
      "a journal that can't be moved aside is never overwritten and blocks changes")
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scratch.path)
  }
  try? FileManager.default.removeItem(at: scratch)
  Engine.folder = realFolder
  Engine.journalBlocked = nil

  do {
    let realApp = MusicLaunch.app
    let realLaunchctl = Engine.launchctl
    Engine.folder = scratch
    MusicLaunch.app = scratch.appendingPathComponent("Music.app")
    defer {
      Engine.folder = realFolder
      MusicLaunch.app = realApp
      Engine.launchctl = realLaunchctl
      try? FileManager.default.removeItem(at: scratch)
    }
    var disabled: Set<String> = ["com.example.unrelated"]
    var running = Set<String>()
    var failEnable = Set<String>()
    var failStop = false
    Engine.launchctl = { args in
      let label = args.last?.split(separator: "/").last.map(String.init) ?? ""
      switch args.first {
      case "print-disabled":
        return .init(status: 0, output: disabled.sorted().map { "\"\($0)\" => disabled" }.joined(separator: "\n"))
      case "print": return .init(status: running.contains(label) ? 0 : 113, output: "")
      case "disable": disabled.insert(label)
      case "enable":
        if failEnable.contains(label) { return .init(status: 5, output: "enable failed") }
        disabled.remove(label)
      case "bootout":
        if failStop { return .init(status: 5, output: "stop failed") }
        running.remove(label)
      default: return .init(status: 1, output: "unexpected launchctl operation")
      }
      return .init(status: 0, output: "")
    }
    let tweak = Tweaks.tweak("music-launches")!
    var journal = Engine.Journal()
    check(tweak.presets.isEmpty && !tweak.inProfile,
      "blocking manual Music launches is opt-in and needs no profile")
    check(!Engine.apply(tweak, journal: &journal).isEmpty && journal.entries.isEmpty
      && disabled == ["com.example.unrelated"],
      "missing Music files fail without disabling an unrelated job")
    do {
      let executable = MusicLaunch.app.appendingPathComponent("Contents/MacOS/Music")
      try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("first".utf8).write(to: executable)
      let first = try MusicLaunch.label()
      running.insert(first)
      check(Engine.apply(tweak, journal: &journal).isEmpty && disabled.contains(first) && running.isEmpty
        && Snapshot().state(tweak) == .applied,
        "applying the Music tweak disables its launch entry and closes the running app")
      try FileManager.default.moveItem(at: executable, to: scratch.appendingPathComponent("old-Music"))
      try Data("replacement".utf8).write(to: executable)
      let second = try MusicLaunch.label()
      check(first != second && Snapshot().state(tweak) == .partial,
        "replacing Music changes its launch entry and leaves the tweak visibly partial")
      check(Engine.apply(tweak, journal: &journal).isEmpty && disabled.contains(second)
        && Set(MusicLaunch.recordedLabels(tweak.id, journal: journal)) == [first, second],
        "reapply blocks the replacement and retains the old entry for undo")
      Engine.save(journal)
      failEnable.insert(first)
      check(!Engine.revertAll().isEmpty && disabled.contains(first) && !disabled.contains(second)
        && MusicLaunch.recordedLabels(tweak.id, journal: Engine.loadJournal()) == [first],
        "failed undo keeps only the failed entry for retry while restoring the others")
      failEnable.removeAll()
      check(Engine.revertAll().isEmpty && disabled == ["com.example.unrelated"]
        && Engine.loadJournal().entries.isEmpty && Snapshot().state(tweak) == .notApplied,
        "retry restores all Music launch entries and leaves unrelated jobs alone")
      journal = Engine.Journal()
      disabled.insert(second)
      check(Engine.apply(tweak, journal: &journal).isEmpty && Engine.apply(tweak, journal: &journal).isEmpty
        && Engine.revert(tweak, journal: &journal).isEmpty && disabled.contains(second) && journal.entries.isEmpty,
        "undo preserves a Music entry that was disabled before applying, even after reapply")
      disabled.remove(second)
      running.insert(second)
      failStop = true
      check(!Engine.apply(tweak, journal: &journal).isEmpty && disabled.contains(second) && running.contains(second)
        && Snapshot().state(tweak) == .partial,
        "failure to stop a running Music app is reported and remains repairable")
      failStop = false
      check(Engine.apply(tweak, journal: &journal).isEmpty && running.isEmpty
        && Engine.revert(tweak, journal: &journal).isEmpty && disabled == ["com.example.unrelated"],
        "a failed stop can be retried without overwriting the original enabled state")
    } catch { check(false, "Music launch lifecycle: \(error)") }
  }

  // Partly applied tweaks are the person's own settings until they ask.
  var s = Snapshot()
  s.profile = Profile.Installed(on: true, ai: false, kept: [], tweaks: ["analytics"])
  let states: [String: TweakState] = ["smart-punctuation": .partial, "autocorrect": .applied, "analytics": .partial]
  let fake: (Tweak) -> TweakState = { states[$0.id] ?? .notApplied }
  let applyOne = Plan.make(wanted: ["autocorrect", "file-extensions"], ai: nil, snapshot: s, state: fake)
  check(applyOne.apply.map(\.id) == ["file-extensions"] && applyOne.revert.isEmpty && applyOne.profile == nil,
    "applying a tweak leaves partly applied ones and the profile alone")
  let undoOne = Plan.make(wanted: ["autocorrect"], ai: nil, undo: ["smart-punctuation"], snapshot: s, state: fake)
  check(undoOne.revert.map(\.id) == ["smart-punctuation"] && undoOne.profile == nil,
    "a partly applied tweak is undone when named")
  let undoLocked = Plan.make(wanted: ["autocorrect"], ai: nil, undo: ["analytics"], snapshot: s, state: fake)
  check(undoLocked.profile?.tweaks == [] && undoLocked.revert.map(\.id) == ["analytics"],
    "a partly applied profile tweak leaves the profile when named")

  MainActor.assumeIsolated {
    let model = AppModel()
    let partialTweak = Tweaks.tweak("smart-punctuation")!
    model.states = Dictionary(uniqueKeysWithValues: Tweaks.all.map { ($0.id, TweakState.notApplied) })
    model.states[partialTweak.id] = .partial
    model.wanted = []
    model.touched = []
    model.toggle(partialTweak, false)
    check(model.pendingTweaks.isEmpty, "switching off a partly applied tweak that is already off changes nothing")
    model.toggle(partialTweak, true)
    model.leave(partialTweak)
    check(model.pendingTweaks.isEmpty, "leaving a partly applied tweak drops an earlier selection")
    model.toggle(partialTweak, true)
    model.toggle(partialTweak, false)
    check(model.pendingTweaks.map(\.tweak.id) == [partialTweak.id] && model.pendingTweaks.first?.apply == false,
      "switching a partly applied tweak on and off undoes it")
  }

  print(failed == 0 ? Term.green("all checks passed") : Term.red("\(failed) failed"))
  return failed == 0
}
