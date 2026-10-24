import Foundation

/// The debloater commands: tweaks, presets, background items, storage and export.
enum TweakCommands {
  static func label(_ state: TweakState) -> String {
    switch state {
    case .applied: return Term.green("done")
    case .notApplied: return Term.dim("not applied")
    case .partial: return Term.yellow("partly")
    case .managed: return Term.yellow("managed by another profile")
    case .unsupported: return Term.dim("needs a newer macOS")
    }
  }

  // MARK: tweaks

  static func list(json: Bool) {
    let s = Snapshot()
    if json {
      let rows = Tweaks.all.map { t -> [String: Any] in
        ["id": t.id, "group": t.group.rawValue, "title": t.title, "state": "\(s.state(t))",
         "profile": t.inProfile, "presets": t.presets.map(\.rawValue).sorted()]
      }
      let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
      print(String(decoding: data, as: UTF8.self))
      return
    }
    Commands.header()
    for group in TweakGroup.allCases {
      print(Term.bold(group.title))
      for t in Tweaks.all where t.group == group {
        print("  " + Term.pad(t.id, 22) + Term.pad(t.title, 46) + label(s.state(t)))
      }
      print()
    }
    print(Term.dim("Apply some with: removemacai apply <names>   or a preset: removemacai apply --preset recommended"))
  }

  // MARK: apply and undo

  /// Applies the named tweaks (and, for a preset, turns Apple Intelligence off),
  /// leaving everything else as it is.
  static func apply(ids: [String], preset: Preset?, dryRun: Bool, yes: Bool) -> Bool {
    let s = Snapshot()
    var requested = Set<String>()
    for id in ids {
      guard let tweak = Tweaks.tweak(id) else {
        Term.fail("there is no tweak called \"\(id)\". The names are listed by: removemacai tweaks")
      }
      requested.insert(tweak.id)
    }
    if let preset { requested.formUnion(Tweaks.preset(preset).map(\.id)) }
    guard !requested.isEmpty else { Term.fail("name the tweaks to apply, or a preset with --preset") }
    let currentAI: Set<String>? = s.profile.ai && s.profile.on ? s.profile.kept : nil
    let ai: Set<String>? = preset != nil ? (currentAI ?? []) : currentAI
    let plan = Plan.make(wanted: s.appliedTweaks.union(requested), ai: ai, snapshot: s)
    return run(plan, dryRun: dryRun, yes: yes, verb: "Apply")
  }

  static func undo(ids: [String], dryRun: Bool, yes: Bool) -> Bool {
    guard !ids.isEmpty else {
      Term.fail("name the tweaks to undo")
    }

    let s = Snapshot()
    var wanted = s.appliedTweaks
    for id in ids {
      guard Tweaks.tweak(id) != nil else { Term.fail("there is no tweak called \"\(id)\"") }
      wanted.remove(id)
    }
    let ai: Set<String>? = s.profile.on && s.profile.ai ? s.profile.kept : nil
    let plan = Plan.make(wanted: wanted, ai: ai, undo: Set(ids), snapshot: s)
    return run(plan, dryRun: dryRun, yes: yes, verb: "Undo")
  }

  static func describe(_ plan: Plan) {
    if !plan.apply.isEmpty {
      print(Term.bold("Apply"))
      for t in plan.apply {
        print("  " + Term.green("+") + " " + t.title)
        for c in t.changes { print("      " + Term.dim(c.command)) }
        if let caveat = t.caveat { print("      " + Term.yellow(caveat)) }
      }
    }
    if !plan.revert.isEmpty {
      print(Term.bold("Undo"))
      for t in plan.revert { print("  " + Term.yellow("-") + " " + t.title) }
    }
    if let profile = plan.profile {
      print(Term.bold("Profile"))
      print("  " + (profile.isEmpty ? "remove the RemoveMacAI profile" : "install the updated profile (macOS asks you to approve it in System Settings)"))
    }
    if !plan.models.isEmpty {
      print(Term.bold("Models"))
      for name in plan.models { print("  delete " + (Catalog.modelSet(name)?.title ?? name)) }
    }
    print()
  }

  static func run(_ plan: Plan, dryRun: Bool, yes: Bool, verb: String) -> Bool {
    Commands.header()
    guard !plan.isEmpty else {
      print(Term.green("Nothing to change.") + " Everything named is already that way.")
      return true
    }
    describe(plan)
    if dryRun {
      print(Term.bold("Dry run, nothing changed."))
      return true
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      guard Term.ask("\(verb) these changes?") else {
        print("Nothing changed.")
        return true
      }
      print()
    }
    let problems = Engine.runLocal(plan)
    for p in problems { print("  " + Term.yellow("!") + " " + p) }
    if !(plan.apply + plan.revert).filter({ !$0.inProfile }).isEmpty {
      print(Term.green("✓") + " Settings changed")
    }
    var ok = problems.isEmpty
    if let profile = plan.profile {
      ok = (profile.isEmpty ? Commands.removeProfile() : Commands.installProfile(profile)) && ok
    }
    if ok && !plan.models.isEmpty {
      ok = Commands.deleteModels(plan.models, step: "Models")
    }
    print()
    print((ok ? Term.green("Done.") : Term.yellow("Incomplete.")) + Term.dim("  Undo everything with: \(Commands.undo)"))
    return ok
  }

  // MARK: background items

  static func background(_ args: [String], yes: Bool) -> Bool {
    if let action = args.first, action != "off" && action != "on" {
      Term.fail("unknown action \"\(action)\", use off or on")
    }
    let items = BackgroundItems.scan()
    let labels = BackgroundItems.disabledLabels()
    guard let action = args.first else {
      Commands.header()
      if items.isEmpty {
        print("No background items from other apps.")
        return true
      }
      print(Term.bold("Background items from other apps"))
      for item in items {
        let off = BackgroundItems.isDisabled(item, labels)
        let state = off ? Term.dim(Term.pad("off", 5)) : Term.green(Term.pad("on", 5))
        let kind = item.isUpdater ? Term.dim("updater") : Term.yellow("helper")
        print("  " + Term.pad(item.label, 48) + Term.pad(item.owner, 22) + state + kind
          + (item.system ? Term.dim("  (all users)") : ""))
      }
      print()
      print(Term.dim("Turning off a helper can stop its app working, for example a VPN or Docker."))
      print(Term.dim("Turn one off with: removemacai background off <label>"))
      return true
    }
    let names = Set(args.dropFirst())
    let chosen = items.filter { names.contains($0.label) }
    for name in names where !chosen.contains(where: { $0.label == name }) {
      Term.fail("there is no background item called \"\(name)\"")
    }
    guard !chosen.isEmpty else { Term.fail("name the items, as listed by: removemacai background") }
    if action == "off" {
      for item in chosen { if let warning = item.warning { print(Term.yellow("!") + " \(item.label): " + warning) } }
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      let verb = action == "off" ? "Turn off" : "Turn on"
      guard Term.ask("\(verb) \(chosen.map(\.label).joined(separator: ", "))?") else {
        print("Nothing changed.")
        return true
      }
    }
    let problems = BackgroundItems.set(chosen, disabled: action == "off")
    for p in problems { print(Term.yellow("!") + " " + p) }
    if problems.isEmpty { print(Term.green("✓") + " " + (action == "off" ? "Turned off" : "Turned on") + ": " + chosen.map(\.label).joined(separator: ", ")) }
    return problems.isEmpty
  }

  // MARK: storage

  static func clean(ids: [String], dryRun: Bool, yes: Bool) -> Bool {
    Commands.header()
    print(Term.dim("Measuring..."))
    let items = Storage.scan()
    if Term.color { print("\u{1B}[1A\u{1B}[K", terminator: "") }
    if items.isEmpty {
      print("Nothing to clean.")
      return true
    }
    print(Term.bold("Space you can get back"))
    for item in items {
      let amount = item.kind == .snapshots ? "\(item.count) snapshots" : Term.size(item.bytes)
      print("  " + Term.pad(item.id, 16) + Term.pad(item.title, 34) + amount)
      if let caveat = item.caveat { print("    " + Term.dim(caveat)) }
    }
    print()
    guard !ids.isEmpty else {
      print(Term.dim("Move some to the Trash with: removemacai clean <names>"))
      return true
    }
    let chosen = items.filter { ids.contains($0.id) }
    for id in ids where !chosen.contains(where: { $0.id == id }) {
      Term.fail("\"\(id)\" is not in the list above")
    }
    let total = chosen.reduce(Int64(0)) { $0 + $1.bytes }
    let permanent = chosen.filter(\.permanent)
    if !permanent.isEmpty {
      print(Term.yellow("!") + " " + permanent.map(\.title).joined(separator: " and ") + " are deleted right away, not moved to the Trash.")
    }
    if dryRun {
      print(Term.bold("Dry run, nothing moved.") + " It would free about \(Term.size(total)).")
      return true
    }
    if !yes {
      guard isatty(STDIN_FILENO) == 1 else { Term.fail("run it in a terminal, or add --yes") }
      let verb = permanent.isEmpty ? "Move" : "Remove"
      let suffix = permanent.isEmpty ? " to the Trash" : ""
      guard Term.ask("\(verb) \(chosen.map(\.title).joined(separator: ", "))\(suffix)?") else {
        print("Nothing moved.")
        return true
      }
    }
    let result = Storage.clean(chosen)
    for p in result.problems { print(Term.yellow("!") + " " + p) }
    let trashed = chosen.filter { !$0.permanent }.reduce(Int64(0)) { $0 + $1.bytes } - result.protectedBytes
    if trashed > 0 { print(Term.green("✓") + " Moved to the Trash. Empty the Trash to free about \(Term.size(trashed)).") }
    if !permanent.isEmpty && result.problems.isEmpty { print(Term.green("✓") + " Deleted " + permanent.map(\.title).joined(separator: " and ") + ".") }
    if result.protected > 0 { print(Term.dim("  \(result.protected) item(s) macOS protects stayed where they were.")) }
    return result.problems.isEmpty
  }

  // MARK: export

  /// Writes the profile for a preset or named tweaks, for deploying with an MDM.
  static func export(path: String, ids: [String], preset: Preset?, keepAI: Set<String>, noAI: Bool) {
    var tweaks = Set<String>()
    for id in ids {
      guard let t = Tweaks.tweak(id) else { Term.fail("there is no tweak called \"\(id)\"") }
      guard t.inProfile else { Term.fail("\(id) is a per-user setting, so it can't go in a profile") }
      tweaks.insert(id)
    }
    if let preset { tweaks.formUnion(Tweaks.preset(preset).filter(\.inProfile).map(\.id)) }
    let contents = Profile.Contents(ai: noAI ? nil : keepAI, tweaks: tweaks)
    do {
      try Profile.data(contents).write(to: URL(fileURLWithPath: path))
    } catch { Term.fail("could not write \(path): \(error)") }
    print(Term.green("✓") + " Wrote \(path)")
    print(Term.dim("  Apple Intelligence: \(noAI ? "left alone" : keepAI.isEmpty ? "off" : "off except \(keepAI.sorted().joined(separator: ", "))")"))
    print(Term.dim("  Tweaks: \(tweaks.isEmpty ? "none" : tweaks.sorted().joined(separator: ", "))"))
    print(Term.dim("  Per-user tweaks (Finder, Dock, typing) aren't in profiles; run removemacai on each Mac for those."))
  }
}
