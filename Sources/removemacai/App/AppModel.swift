import AppKit
import Observation
import SwiftUI

enum Page: Hashable {
  case overview, intelligence, group(TweakGroup), background, storage, changes

  var title: String {
    switch self {
    case .overview: return "Overview"
    case .intelligence: return "Apple Intelligence"
    case .group(let g): return g.title
    case .background: return "Background Items"
    case .storage: return "Storage"
    case .changes: return "Undo"
    }
  }

  var symbol: String {
    switch self {
    case .overview: return "gauge.with.dots.needle.33percent"
    case .intelligence: return "apple.intelligence"
    case .group(let g): return g.symbol
    case .background: return "gearshape.2"
    case .storage: return "internaldrive"
    case .changes: return "arrow.uturn.backward"
    }
  }
}

/// What the app is doing after Apply.
enum RunState: Equatable {
  case working(String)
  case approveProfile(remove: Bool)
  case finished(problems: [String], freed: Int64?)
}

@MainActor @Observable
final class AppModel {
  var page: Page? = .overview

  // What the Mac looks like now.
  var snapshot = Snapshot()
  var featureStates: [String: FeatureState] = [:]
  var modelBytes: [String: Int64] = [:]
  var modelsAvailable = true
  var loadingModels = true
  var journal = Engine.loadJournal()

  // What the person wants.
  var wanted: Set<String> = []
  /// Tweaks the person switched, so a partly applied one is only undone on request.
  var touched: Set<String> = []
  var aiOff = false
  var aiKept: Set<String> = []

  var background: [BackgroundItem] = []
  var backgroundOff: Set<String> = []
  var backgroundBusy = false

  var storage: [StorageItem] = []
  var storageChosen: Set<String> = []
  var scanning = false
  var scanned = false
  var cleaning = false
  var cleanMessage: String?

  var reviewing = false
  var run: RunState?
  private var cancelWait = false

  var showingWelcome = false
  var welcomePage = 0
  static let welcomeSeenKey = "WelcomeSeen"

  static weak var shared: AppModel?

  init() {
    reload(resetChoices: true)
    AppModel.shared = self
    if !UserDefaults.standard.bool(forKey: Self.welcomeSeenKey) { showingWelcome = true }
  }

  func openWelcome() {
    welcomePage = 0
    showingWelcome = true
  }

  func closeWelcome() {
    showingWelcome = false
    UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
  }

  // MARK: reading

  var currentAI: Set<String>? { snapshot.profile.on && snapshot.profile.ai ? snapshot.profile.kept : nil }
  var targetAI: Set<String>? { aiOff ? aiKept : nil }

  /// Each tweak's state, read once per reload; the views ask for it on every redraw.
  var states: [String: TweakState] = [:]

  func reload(resetChoices: Bool) {
    snapshot = Snapshot()
    states = Dictionary(uniqueKeysWithValues: Tweaks.all.map { ($0.id, snapshot.state($0)) })
    journal = Engine.loadJournal()
    if resetChoices {
      wanted = Set(states.filter { $0.value == .applied }.map(\.key))
      touched = []
      aiOff = currentAI != nil
      aiKept = snapshot.profile.ai ? snapshot.profile.kept : []
    }
    loadBackground()
    loadModels()
  }

  func loadModels() {
    loadingModels = true
    Task.detached(priority: .userInitiated) {
      let available = Models.available()
      var bytes: [String: Int64] = [:]
      if available {
        for set in Catalog.availableModelSets { if let b = Models.bytes(set.name) { bytes[set.name] = b } }
      }
      let states = Dictionary(uniqueKeysWithValues: Catalog.availableFeatures.map { ($0.id, Settings.state($0)) })
      let sizes = bytes
      await MainActor.run {
        self.modelsAvailable = available
        self.modelBytes = sizes
        self.featureStates = states
        self.loadingModels = false
      }
    }
  }

  var modelTotal: Int64 { modelBytes.values.reduce(0, +) }

  /// The size of these sets, or nil unless every one of them has a reading.
  func modelBytes(_ sets: [String]) -> Int64? { Models.total(sets, read: { self.modelBytes[$0] }) }

  func loadBackground() {
    background = BackgroundItems.scan()
    let labels = BackgroundItems.disabledLabels()
    backgroundOff = Set(background.filter { BackgroundItems.isDisabled($0, labels) }.map(\.id))
  }

  func state(_ tweak: Tweak) -> TweakState { states[tweak.id] ?? snapshot.state(tweak) }

  func isOn(_ tweak: Tweak) -> Bool { wanted.contains(tweak.id) }

  func toggle(_ tweak: Tweak, _ on: Bool) {
    guard wanted.contains(tweak.id) != on else { return }
    touched.insert(tweak.id)
    if on { wanted.insert(tweak.id) } else { wanted.remove(tweak.id) }
  }

  /// Drops any choice made for the tweak, so it stays as it is on the Mac.
  func leave(_ tweak: Tweak) {
    wanted.remove(tweak.id)
    touched.remove(tweak.id)
  }

  /// Whether leaving the tweak unwanted undoes it.
  func undoes(_ tweak: Tweak) -> Bool {
    let s = state(tweak)
    guard !wanted.contains(tweak.id), s != .notApplied, s != .managed, s != .unsupported else { return false }
    return s != .partial || touched.contains(tweak.id)
  }

  func choose(_ preset: Preset) {
    wanted.formUnion(Tweaks.preset(preset).map(\.id))
    aiOff = true
  }

  var appliedCount: Int { states.values.filter { $0 == .applied }.count }
  var availableCount: Int { Tweaks.all.filter { let s = state($0); return s != .unsupported && s != .managed }.count }

  /// Tweaks whose wanted state differs from the Mac.
  var pendingTweaks: [(tweak: Tweak, apply: Bool)] {
    Tweaks.all.compactMap { t in
      let s = state(t)
      guard s != .managed && s != .unsupported else { return nil }
      if wanted.contains(t.id) && s != .applied { return (t, true) }
      if undoes(t) { return (t, false) }
      return nil
    }
  }

  var aiPending: Bool { targetAI != currentAI }
  var pendingCount: Int { pendingTweaks.count + (aiPending ? 1 : 0) }

  func pending(in group: TweakGroup) -> Int { pendingTweaks.filter { $0.tweak.group == group }.count }

  /// Switches on in a group, out of the ones that can change, for the sidebar.
  func switchedOn(in group: TweakGroup) -> (on: Int, total: Int) {
    let tweaks = Tweaks.all.filter { $0.group == group && state($0) != .unsupported && state($0) != .managed }
    return (tweaks.filter { wanted.contains($0.id) }.count, tweaks.count)
  }

  func discard() { reload(resetChoices: true) }

  func plan() -> Plan { Plan.make(wanted: wanted, ai: targetAI, undo: touched, snapshot: snapshot) }

  // MARK: applying

  func apply() {
    let plan = plan()
    reviewing = false
    run = .working("Changing settings")
    cancelWait = false
    Task.detached(priority: .userInitiated) {
      var problems = Engine.runLocal(plan)
      var freed: Int64? = nil
      if let target = plan.profile {
        await MainActor.run { self.run = .approveProfile(remove: target.isEmpty) }
        if !target.isEmpty {
          do { try Profile.present(target) } catch { problems.append("Could not write the profile: \(error)") }
          try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await MainActor.run { Commands.openProfileSettings() }
        let approved = await self.waitFor { target.isEmpty ? !Profile.installed().on : Profile.matches(target) }
        if !approved {
          problems.append(
            target.isEmpty
              ? "The profile is still installed. Remove RemoveMacAI in System Settings > General > Device Management."
              : "The profile wasn't approved, so the locked settings and Apple Intelligence didn't change.")
        }
      }
      // Models only go once the profile blocks their download.
      if !plan.models.isEmpty && Profile.installed().ai {
        await MainActor.run { self.run = .working("Deleting Apple Intelligence models") }
        let result = Self.deleteModels(plan.models)
        problems += result.problems
        freed = result.freed
      }
      let outcome = RunState.finished(problems: problems, freed: freed)
      await MainActor.run {
        self.run = outcome
        self.reload(resetChoices: true)
      }
    }
  }

  nonisolated static func deleteModels(_ sets: [String]) -> (problems: [String], freed: Int64?) {
    guard Models.available() else { return (["Apple's asset service didn't answer, so the models stay for now."], nil) }
    var problems: [String] = []
    var removing = sets
    do {
      let split = try Models.matching(sets)
      removing = split.matched
      problems += split.skipped.map { "\(Catalog.modelSet($0.0)?.title ?? $0.0) stayed: \($0.1)" }
    } catch { return (["\(error)"], nil) }
    let before = Models.total(removing)
    do {
      let result = try Commands.removeModels(removing, before: before)
      problems += result.failures.map { "\(Catalog.modelSet($0.0)?.title ?? $0.0): \($0.1)" }
      if !result.verified { problems.append("Removal couldn't be confirmed yet. Check again in a minute.") }
      return (problems, result.deletedBytes)
    } catch {
      return (problems + ["\(error)"], nil)
    }
  }

  /// Polls until the condition holds, Cancel is pressed, or ten minutes pass.
  nonisolated func waitFor(_ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(600)
    while Date() < deadline {
      if condition() { return true }
      if await MainActor.run(body: { self.cancelWait }) { return false }
      try? await Task.sleep(nanoseconds: 700_000_000)
    }
    return false
  }

  func cancel() { cancelWait = true }

  /// Deletes models left on disk while Apple Intelligence is already off.
  func deleteLeftoverModels() {
    guard let kept = currentAI else { return }
    run = .working("Deleting Apple Intelligence models")
    Task.detached(priority: .userInitiated) {
      let sets = Catalog.setsToRemove(keeping: kept).filter { Models.present($0) }
      let result = Self.deleteModels(sets)
      let outcome = RunState.finished(problems: result.problems, freed: result.freed)
      await MainActor.run {
        self.run = outcome
        self.reload(resetChoices: false)
      }
    }
  }

  func dismissRun() { run = nil }

  // MARK: undo

  func undoEverything() {
    run = .working("Undoing changes")
    cancelWait = false
    Task.detached(priority: .userInitiated) {
      var problems = Engine.revertAll()
      if Profile.installed().on {
        await MainActor.run {
          self.run = .approveProfile(remove: true)
          Commands.openProfileSettings()
        }
        if !(await self.waitFor { !Profile.installed().on }) {
          problems.append("The profile is still installed. Remove RemoveMacAI in System Settings > General > Device Management.")
        }
      }
      let outcome = RunState.finished(problems: problems, freed: nil)
      await MainActor.run {
        self.run = outcome
        self.reload(resetChoices: true)
      }
    }
  }

  // MARK: background items

  func setBackground(_ item: BackgroundItem, off: Bool) {
    backgroundBusy = true
    Task.detached(priority: .userInitiated) {
      let problems = BackgroundItems.set([item], disabled: off)
      await MainActor.run {
        self.backgroundBusy = false
        self.loadBackground()
        self.journal = Engine.loadJournal()
        if !problems.isEmpty { self.run = .finished(problems: problems, freed: nil) }
      }
    }
  }

  // MARK: storage

  func scan() {
    scanning = true
    cleanMessage = nil
    Task.detached(priority: .userInitiated) {
      let items = Storage.scan()
      await MainActor.run {
        self.storage = items
        self.storageChosen = Set(items.filter { ["derived-data", "installers", "ios-firmware", "simulators"].contains($0.id) }.map(\.id))
        self.scanning = false
        self.scanned = true
      }
    }
  }

  var chosenBytes: Int64 { storage.filter { storageChosen.contains($0.id) }.reduce(0) { $0 + $1.bytes } }

  func clean() {
    let chosen = storage.filter { storageChosen.contains($0.id) }
    cleaning = true
    Task.detached(priority: .userInitiated) {
      let result = Storage.clean(chosen)
      let items = Storage.scan()
      let trashedIDs = chosen.filter { !$0.permanent }.map(\.id)
      let trashedTotal = chosen.filter { !$0.permanent }.reduce(Int64(0)) { $0 + $1.bytes }
      let left = items.filter { trashedIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.bytes }
      var parts: [String] = []
      if !trashedIDs.isEmpty { parts.append("Moved \(Term.size(max(0, trashedTotal - left))) to the Trash. Empty the Trash to free the space.") }
      let permanent = chosen.filter(\.permanent)
      if !permanent.isEmpty && result.problems.isEmpty {
        parts.append("Deleted \(permanent.map(\.title).joined(separator: " and ")).")
      }
      var message = parts.joined(separator: " ")
      if result.protected > 0 {
        message += " \(result.protected) item\(result.protected == 1 ? "" : "s") macOS protects stayed where \(result.protected == 1 ? "it was" : "they were")."
      }
      if !result.problems.isEmpty { message += "\n" + result.problems.joined(separator: "\n") }
      let finalMessage = message
      await MainActor.run {
        self.cleaning = false
        self.storage = items
        self.storageChosen = []
        self.cleanMessage = finalMessage
      }
    }
  }
}
