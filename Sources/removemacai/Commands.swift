import AppKit
import Foundation

let version = "0.2.1"

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
    for feature in Catalog.features {
      let label: String
      switch Settings.state(feature) {
      case .lockedOff: label = Term.green("off") + Term.dim(" (locked)")
      case .off: label = Term.green("off")
      case .on: label = Term.yellow("on")
      }
      print("  " + Term.pad(feature.title, 40) + label)
    }
    print()
    if printModels() == 0 && Profile.installed().on && Models.available() {
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
  static func printModels() -> Int64 {
    print(Term.bold("Models on disk"))
    guard Models.available() else {
      print(Term.dim("  Apple's asset service did not answer, so the sizes are unknown."))
      return 0
    }
    var total: Int64 = 0
    for set in Catalog.modelSets {
      let bytes = Models.bytes(set.name) ?? 0
      total += bytes
      print("  " + Term.pad(set.title, 40) + (bytes > 0 ? Term.yellow(Term.size(bytes)) : Term.dim("none")))
    }
    print("  " + Term.pad("Total", 40) + Term.bold(Term.size(total)))
    return total
  }

  static func featuresOn() -> Int { Catalog.features.filter { Settings.state($0) == .on }.count }

  static func isOff() -> Bool {
    Profile.installed().on && featuresOn() == 0
  }

  // MARK: off

  static func off(keep: Set<String>, dryRun: Bool, yes: Bool) {
    header()
    for id in keep where Catalog.feature(id) == nil {
      Term.fail("there is no feature called \"\(id)\". The names are listed by: removemacai features")
    }
    let sets = Catalog.setsToRemove(keeping: keep)
    let modelsKnown = Models.available()
    let modelsBefore = modelsKnown ? Models.total(sets) : 0
    // The service's sizes miss files it no longer tracks, so a set counts as
    // still there while its folder exists.
    let remaining = modelsKnown ? sets.filter(Models.present) : []
    let modelsSize = modelsBefore > 0 ? Term.size(modelsBefore) : "an unknown amount"
    let profile = Profile.installed()
    let unknownModels = "Apple's asset service did not answer, so the models on disk were not deleted."

    if profile.on && profile.kept == keep && profile.current && remaining.isEmpty {
      print(Term.green("Apple Intelligence is already off") + (modelsKnown ? " and its models are gone." : "."))
      print(modelsKnown
        ? Term.dim("macOS removes deleted model files itself, so System Settings can count them for a while.")
        : Term.yellow("!") + " " + unknownModels)
      print(Term.dim("Check it with: removemacai status    Undo with: \(undo)"))
      return
    }

    let on = featuresOn()
    print(!profile.on ? "Apple Intelligence is on."
      : !profile.current ? "The installed profile is from an older RemoveMacAI and misses some switches."
      : "Apple Intelligence is off, but some models are back.")
    print("  " + Term.pad("Features on", 20) + "\(on) of \(Catalog.features.count)")
    print("  " + Term.pad("Models on disk", 20) + (modelsKnown ? modelsSize : "unknown"))
    print()
    print("Turning it off will:")
    print("  · switch off Siri, dictation, Writing Tools, Genmoji, Image Playground, summaries and ChatGPT"
      + (keep.isEmpty ? "" : Term.dim(" (keeping " + keep.sorted().joined(separator: ", ") + ")")))
    print(modelsKnown
      ? "  · delete " + Term.bold(modelsSize) + " of models and stop macOS downloading them again"
      : "  · stop macOS downloading the models (Apple's asset service did not answer, so the ones on disk stay)")
    if !(profile.on && profile.kept == keep && profile.current) {
      print("  · ask you to approve one profile in System Settings (macOS requires that click)")
    }
    print()
    print(Term.dim("Everything comes back with: \(undo)"))
    print()

    let data: Data
    do { data = try Profile.data(keeping: keep) } catch { Term.fail("could not build the profile: \(error)") }

    if dryRun {
      let path = FileManager.default.temporaryDirectory.appendingPathComponent("RemoveMacAI.mobileconfig")
      try? data.write(to: path)
      print(Term.bold("Dry run, nothing changed."))
      print("Profile it would install:  " + path.path)
      print("Models it would delete:    " + (remaining.isEmpty ? "none" : remaining.joined(separator: ", ")))
      return
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      guard Term.ask("Turn Apple Intelligence off?") else {
        print("Nothing changed.")
        return
      }
      print()
    }

    // 1. The profile switches the features off and blocks the model downloads.
    if profile.on && profile.kept == keep && profile.current {
      print(Term.green("✓") + " The profile is already installed")
    } else {
      print(Term.bold("Step 1 of 2") + "  Approve the profile")
      do { try data.write(to: Profile.file) } catch { Term.fail("could not write \(Profile.file.path): \(error)") }
      NSWorkspace.shared.open(Profile.file)
      Thread.sleep(forTimeInterval: 1)
      openProfileSettings()
      print("  System Settings is open. Double-click " + Term.bold("RemoveMacAI") + ", then click "
        + Term.bold("Install") + ".")
      guard waitFor("waiting for you in System Settings", { let p = Profile.installed(); return p.on && p.kept == keep && p.current })
      else {
        print("  The profile is not installed yet. Run this again once it is, and it picks up from here.")
        exit(1)
      }
      print("  " + Term.green("✓") + " Profile installed")
    }

    // 2. The models go now that they cannot download again. Check again: a
    // set can download while the profile waits for approval.
    let present = modelsKnown ? sets.filter(Models.present) : []
    if !modelsKnown {
      print("  " + Term.yellow("!") + " " + unknownModels)
    } else if !present.isEmpty {
      print(Term.bold("Step 2 of 2") + "  Delete the models")
      do {
        for (name, reason) in try Models.remove(present) {
          print("  " + Term.yellow("!") + " \(Catalog.modelSet(name)?.title ?? name) stayed: " + Term.dim(reason))
        }
      } catch { Term.fail("\(error)") }
      _ = waitFor("deleting", { Models.total(sets) == 0 }, minutes: 0.5)
      let freed = max(0, modelsBefore - Models.total(sets))
      print("  " + Term.green("✓") + (freed > 0 ? " Deleted " + Term.size(freed) : " Asked macOS to delete them"))
      print("    " + Term.dim("macOS removes the files itself, so System Settings can count them under Apple Intelligence for a while."))
      print("    " + Term.dim("See what is left with: removemacai scan"))
    }
    print()
    print(Term.green("Done.") + " Apple Intelligence is off.")
    print(Term.dim("Check it with: removemacai status    Undo with: \(undo)"))
  }

  // MARK: revert

  static func revert() {
    header()
    guard Profile.installed().on else {
      print("The RemoveMacAI profile is not installed, so there is nothing to undo.")
      return
    }
    openProfileSettings()
    print("System Settings is open. Select " + Term.bold("RemoveMacAI") + ", then click " + Term.bold("Remove") + ".")
    print(Term.dim("From a terminal instead: sudo profiles remove -identifier \(Profile.identifier)"))
    guard waitFor("waiting for you in System Settings", { !Profile.installed().on }) else {
      print("The profile is still installed. You can remove it in System Settings any time.")
      exit(1)
    }
    print(Term.green("✓") + " Profile removed. Your own settings apply again.")
    print(Term.dim("macOS downloads the models again when you turn a feature back on."))
  }

  // MARK: features

  static func features() {
    for f in Catalog.features { print(Term.pad(f.id, 26) + f.title) }
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
