import AppKit
import Foundation

let version = "1.2.0-beta.2"

enum Commands {
  /// How to undo, as the person ran us: the one-line installer passes its own
  /// command, a brew or source install uses the binary's name.
  static var undo: String {
    ProcessInfo.processInfo.environment["REMOVEMACAI_UNDO"] ?? "removemacai revert"
  }

  static func header() {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    print(Term.bold("RemoveMacAI") + Term.dim(" \(version)  ·  macOS \(os.majorVersion).\(os.minorVersion)"))
    print()
  }

  // MARK: status

  static func status() {
    header()
    print(Term.bold("Features"))
    for feature in Catalog.availableFeatures {
      let label: String
      switch Settings.state(feature) {
      case .lockedOff: label = Term.green("off") + Term.dim(" (locked)")
      case .off: label = Term.green("off")
      case .on: label = Term.yellow("on")
      case .unknown: label = Term.yellow("unknown")
      }
      print("  " + Term.pad(feature.title, 40) + label)
    }
    print()
    if printModels() == 0 && Profile.installed().ai {
      print(Term.dim("  macOS removes deleted model files itself, so System Settings can count them for a while."))
    }
    print()
    if isOff() {
      print(Term.green("Apple Intelligence is off.") + Term.dim(" Undo with: \(undo)"))
    } else {
      print("Turn it off with: " + Term.bold("removemacai"))
    }
  }

  @discardableResult
  static func printModels() -> Int64? {
    print(Term.bold("Models on disk"))
    guard Models.available() else {
      print(Term.dim("  Apple's asset service did not answer, so the sizes are unknown."))
      return nil
    }
    var readings: [String: Int64] = [:]
    for set in Catalog.availableModelSets {
      let bytes = Models.bytes(set.name)
      readings[set.name] = bytes
      print("  " + Term.pad(set.title, 40) + modelSize(bytes))
    }
    let total = Models.total(Catalog.availableModelSets.map(\.name), read: { readings[$0] })
    print("  " + Term.pad("Total", 40) + (total.map { Term.bold(Term.size($0)) } ?? Term.yellow("unknown")))
    return total
  }

  static func modelSize(_ bytes: Int64?) -> String {
    guard let bytes else { return Term.yellow("unknown") }
    return bytes > 0 ? Term.yellow(Term.size(bytes)) : Term.dim("none")
  }

  static func featuresOn() -> Int { Catalog.availableFeatures.filter { Settings.state($0) == .on }.count }

  static func isOff() -> Bool {
    let profile = Profile.installed()
    return profile.on && profile.ai && Catalog.availableFeatures.allSatisfy { Settings.state($0).isOff }
  }

  // MARK: off

  static func off(keep: Set<String>, dryRun: Bool, yes: Bool) -> Bool {
    header()
    for id in keep where !Catalog.availableFeatures.contains(where: { $0.id == id }) {
      Term.fail("there is no feature called \"\(id)\" on this version of macOS. The names are listed by: removemacai features")
    }
    let sets = Catalog.setsToRemove(keeping: keep)
    let modelsAvailable = sets.isEmpty || Models.available()
    let modelsBefore: Int64? = sets.isEmpty ? 0 : (modelsAvailable ? Models.total(sets) : nil)
    let profile = Profile.installed()
    let target = Profile.Contents(ai: keep, tweaks: profile.tweaks)
    let profileReady = profile.contents == target
    let offSummary = keep.isEmpty ? "Apple Intelligence is off." : "The selected features are off."

    if profileReady && modelsBefore == 0 {
      print(Term.green(offSummary) + " No models remain in the sets selected for removal.")
      if !sets.isEmpty {
        print(Term.dim("macOS removes deleted model files itself, so System Settings can count them for a while."))
      }
      warnKeptButOff(keep)
      print(Term.dim("Check it with: removemacai status    Undo with: \(undo)"))
      return true
    }

    let on = featuresOn()
    print(profileReady ? "The profile is installed. Checking the selected models." : "Checking Apple Intelligence and its models.")
    print("  " + Term.pad("Features on", 20) + "\(on) of \(Catalog.availableFeatures.count)")
    print("  " + Term.pad("Models on disk", 20) + (modelsBefore.map(Term.size) ?? "unknown"))
    print()
    print("Turning it off will:")
    print("  · switch off Siri, Writing Tools, Genmoji, Image Playground, summaries and ChatGPT"
      + (keep.isEmpty ? "" : Term.dim(" (keeping " + keep.sorted().joined(separator: ", ") + ")")))
    if let modelsBefore {
      print("  · delete " + Term.bold(Term.size(modelsBefore)) + " of models and stop macOS downloading them again")
    } else if modelsAvailable {
      print("  · request model removal and block downloads (the current model sizes are unknown)")
    } else {
      print("  · stop model downloads (Apple's asset service is unavailable, so removal cannot be requested)")
    }
    if !profileReady {
      print("  · ask you to approve one profile in System Settings (macOS requires that click)")
    }
    print()
    print(Term.dim("Everything comes back with: \(undo)"))
    print()

    let data: Data
    do { data = try Profile.data(target) } catch { Term.fail("could not build the profile: \(error)") }

    if dryRun {
      let path = FileManager.default.temporaryDirectory.appendingPathComponent("RemoveMacAI.mobileconfig")
      try? data.write(to: path)
      print(Term.bold("Dry run, nothing changed."))
      print("Profile it would install:  " + path.path)
      var deleting = sets
      var staying: [(String, String)] = []
      if modelsAvailable, let split = try? Models.matching(sets) {
        (deleting, staying) = (split.matched.filter { Models.present($0) }, split.skipped)
      }
      print("Models it would delete:    " + (deleting.isEmpty ? "none" : deleting.joined(separator: ", ")))
      for (name, reason) in staying {
        print("  " + Term.yellow("!") + " \(Catalog.modelSet(name)?.title ?? name) would stay: " + Term.dim(reason))
      }
      return true
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      guard Term.ask("Turn Apple Intelligence off?") else {
        print("Nothing changed.")
        return true
      }
      print()
    }

    // 1. The profile switches the features off and blocks the model downloads.
    if profileReady {
      print(Term.green("✓") + " The profile is already installed")
    } else {
      print(Term.bold("Step 1 of 2") + "  Approve the profile")
      do { try data.write(to: Profile.file) } catch { Term.fail("could not write \(Profile.file.path): \(error)") }
      NSWorkspace.shared.open(Profile.file)
      Thread.sleep(forTimeInterval: 1)
      openProfileSettings()
      print("  System Settings is open. Double-click " + Term.bold("RemoveMacAI") + ", then click "
        + Term.bold("Install") + ".")
      guard waitFor("waiting for you in System Settings", { Profile.matches(target) })
      else {
        print("  The profile is not installed yet. Run this again once it is, and it picks up from here.")
        return false
      }
      print("  " + Term.green("✓") + " Profile installed")
    }

    // 2. The models go now that they cannot download again.
    let removalComplete = deleteModels(sets, step: "Step 2 of 2")
    print()
    if removalComplete {
      print(Term.green("Done.") + " " + offSummary)
      print(Term.dim("I make RemoveMacAI by myself. If it was useful, you can sponsor it: https://github.com/sponsors/omlahore"))
    } else {
      print(Term.yellow("Incomplete.") + " " + offSummary + " The profile remains installed; model removal is incomplete.")
    }
    warnKeptButOff(keep)
    print(Term.dim("Check it with: removemacai status    Undo with: \(undo)"))
    return removalComplete
  }

  /// Removes the model sets through the asset service and reports what it
  /// could confirm. Returns whether removal is complete.
  static func deleteModels(_ sets: [String], step: String) -> Bool {
    // Approval can take several minutes; use a fresh snapshot before deleting.
    let removalAvailable = sets.isEmpty || Models.available()
    var removing = sets
    var staying: [(String, String)] = []
    if removalAvailable, !sets.isEmpty {
      do { (removing, staying) = try Models.matching(sets) } catch { Term.fail("\(error)") }
    }
    for (name, reason) in staying {
      print("  " + Term.yellow("!") + " \(Catalog.modelSet(name)?.title ?? name) stayed: " + Term.dim(reason))
    }
    let removalBefore: Int64? = removing.isEmpty ? 0 : (removalAvailable ? Models.total(removing) : nil)
    var removalComplete = true
    if !removalAvailable {
      print("  " + Term.yellow("!") + " Apple's asset service is unavailable, so model removal could not be requested.")
      removalComplete = false
    } else if removalBefore != 0 {
      print(Term.bold(step) + "  Delete the models")
      do {
        let result = try removeModels(removing, before: removalBefore)
        for (name, reason) in result.failures {
          print("  " + Term.yellow("!") + " Removal request for \(Catalog.modelSet(name)?.title ?? name): " + Term.dim(reason))
        }
        removalComplete = result.complete
        if let deleted = result.deletedBytes {
          print("  " + (result.complete ? Term.green("✓") : Term.yellow("!")) + " Deleted " + Term.size(deleted))
        } else {
          print("  " + Term.dim("The amount deleted is unknown because the asset service did not report all sizes."))
        }
        if result.after == nil {
          print("  " + Term.yellow("!") + " The remaining model sizes are unknown; removal could not be confirmed.")
        } else if let remaining = result.after, remaining > 0 {
          print("  " + Term.yellow("!") + " " + Term.size(remaining) + " of selected models remain.")
        }
        if !result.verified {
          print("  " + Term.yellow("!") + " Timed out waiting to confirm that the selected models were removed.")
        }
        if result.complete {
          print("    " + Term.dim("macOS removes the files itself, so System Settings can count them under Apple Intelligence for a while."))
        }
      } catch { Term.fail("\(error)") }
    }
    return removalComplete
  }

  static func warnKeptButOff(_ keep: Set<String>) {
    for feature in Catalog.availableFeatures where keep.contains(feature.id) && Settings.state(feature) == .off {
      print(Term.yellow("!") + " \(feature.title) is kept, but it is switched off. Turn it on in System Settings.")
    }
  }

  /// Injectable operations let self-tests verify failures without contacting the asset service.
  static func removeModels(
    _ sets: [String], before: Int64?,
    remove: ([String]) throws -> [(String, String)] = { try Models.remove($0) },
    total: @escaping ([String]) -> Int64? = { Models.total($0) },
    wait: (() -> Bool) -> Bool = { waitFor("deleting", $0, minutes: 0.5) }
  ) throws -> ModelRemovalResult {
    if sets.isEmpty || before == 0 {
      return ModelRemovalResult(before: before, after: 0, failures: [], verified: true)
    }
    let failures = try remove(sets)
    var after: Int64?
    let verified = wait {
      after = total(sets)
      return after == 0
    }
    return ModelRemovalResult(before: before, after: after, failures: failures, verified: verified)
  }

  // MARK: revert

  /// Undoes everything: the tweaks in the journal right away, then the
  /// profile, which macOS only lets the person remove.
  static func revert() {
    header()
    let journal = Engine.loadJournal()
    let profileOn = Profile.installed().on
    guard profileOn || !journal.entries.isEmpty else {
      print("RemoveMacAI hasn't changed anything on this Mac, so there is nothing to undo.")
      return
    }
    if !journal.entries.isEmpty {
      let problems = Engine.revertAll()
      for p in problems { print("  " + Term.yellow("!") + " " + p) }
      print(Term.green("✓") + " Settings changed outside the profile are back as they were")
    }
    if profileOn {
      guard removeProfile() else { exit(1) }
      print(Term.dim("macOS downloads the models again when you turn a feature back on."))
    }
  }

  /// Turns Apple Intelligence back on and keeps the other tweaks.
  static func on() {
    header()
    let profile = Profile.installed()
    guard profile.on && profile.ai else {
      print("RemoveMacAI isn't turning Apple Intelligence off, so there is nothing to undo.")
      return
    }
    if profile.tweaks.isEmpty {
      guard removeProfile() else { exit(1) }
    } else {
      let target = Profile.Contents(ai: nil, tweaks: profile.tweaks)
      guard installProfile(target) else { exit(1) }
    }
    print(Term.dim("macOS downloads the models again when you turn a feature back on."))
  }

  static func removeProfile() -> Bool {
    openProfileSettings()
    print("System Settings is open. Select " + Term.bold("RemoveMacAI") + ", then click " + Term.bold("Remove") + ".")
    print(Term.dim("From a terminal instead: sudo profiles remove -identifier \(Profile.identifier)"))
    guard waitFor("waiting for you in System Settings", { !Profile.installed().on }) else {
      print("The profile is still installed. You can remove it in System Settings any time.")
      return false
    }
    print(Term.green("✓") + " Profile removed. Your own settings apply again.")
    return true
  }

  /// Shows the profile for approval and waits until it is in force.
  static func installProfile(_ target: Profile.Contents) -> Bool {
    do { try Profile.present(target) } catch {
      print(Term.red("error: ") + "could not write \(Profile.file.path): \(error)")
      return false
    }
    Thread.sleep(forTimeInterval: 1)
    openProfileSettings()
    print("System Settings is open. Double-click " + Term.bold("RemoveMacAI") + ", then click " + Term.bold("Install") + ".")
    guard waitFor("waiting for you in System Settings", { Profile.matches(target) }) else {
      print("The profile is not installed yet. Run this again once it is.")
      return false
    }
    print(Term.green("✓") + " Profile installed")
    return true
  }

  // MARK: features

  static func features(json: Bool) {
    if json {
      let rows = Catalog.availableFeatures.map { ["id": $0.id, "title": $0.title] }
      let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
      print(String(decoding: data, as: UTF8.self))
      return
    }
    for f in Catalog.availableFeatures { print(Term.pad(f.id, 26) + f.title) }
  }

  // MARK: helpers

  static func openProfileSettings() {
    for url in [
      "x-apple.systempreferences:com.apple.Profiles-Settings.extension",
      "x-apple.systempreferences:com.apple.preferences.configurationprofiles",
    ] {
      if let u = URL(string: url), NSWorkspace.shared.open(u) { return }
    }
  }

  static func waitFor(_ what: String, _ condition: () -> Bool, minutes: Double = 10) -> Bool {
    let spinner = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    let deadline = Date().addingTimeInterval(minutes * 60)
    var i = 0
    defer { if Term.color { print("\r\u{1B}[K", terminator: "") } }
    while Date() < deadline {
      if condition() { return true }
      if Term.color {
        print("\r  " + Term.dim("\(spinner[i % spinner.count]) \(what)"), terminator: "")
        fflush(stdout)
      }
      i += 1
      Thread.sleep(forTimeInterval: 0.5)
    }
    return false
  }
}
