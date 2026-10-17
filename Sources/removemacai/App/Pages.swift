import SwiftUI

// MARK: - Overview

struct OverviewView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        StatusHero()
        HStack(spacing: 12) {
          StatTile(title: "Settings changed", value: "\(model.appliedCount) of \(model.availableCount)", link: model.appliedCount > 0 ? "See which ones" : "Browse settings") {
            model.page = .group(TweakGroup.allCases.first { model.switchedOn(in: $0).on > 0 } ?? .privacy)
          }
          StatTile(title: "Apps running in the background", value: model.background.isEmpty ? "None" : "\(model.background.count)", link: "See what they are") {
            model.page = .background
          }
          StatTile(
            title: "Space you can get back",
            value: model.scanned ? Term.size(model.storage.reduce(0) { $0 + $1.bytes }) : "Not checked",
            link: model.scanned ? "Old installers and caches" : "Check now"
          ) {
            model.page = .storage
            if !model.scanned && !model.scanning { model.scan() }
          }
        }
        VStack(alignment: .leading, spacing: 10) {
          Text("Or start with a preset").font(.headline)
          VStack(spacing: 0) {
            ForEach(Array(Preset.allCases.enumerated()), id: \.element) { i, preset in
              if i > 0 { Divider().padding(.leading, 56) }
              HStack(alignment: .top, spacing: 14) {
                Image(systemName: preset == .recommended ? "checkmark.seal" : "hand.raised")
                  .font(.title2).foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                  Text(preset.title).font(.headline)
                  Text(preset.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                  Text("\(Tweaks.preset(preset).count) settings and Apple Intelligence off")
                    .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Review…") {
                  model.choose(preset)
                  model.reviewing = true
                }
              }
              .padding(14)
            }
          }
          .card()
          Footer("A preset adds to what's already applied and changes nothing until you review it.")
        }
        SafetyCard { model.openWelcome() }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        Text("Apple Intelligence removal builds on [pared](https://github.com/4evy/pared) by 4evy.")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .tint(.secondary)
      }
      .padding(24)
      .frame(maxWidth: 820)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Overview")
  }
}

/// Apple Intelligence's state, how much space it takes, and the main action.
struct StatusHero: View {
  @Environment(AppModel.self) private var model

  var off: Bool { model.currentAI != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 16) {
        ZStack {
          RoundedRectangle(cornerRadius: 12).fill((off ? Color.green : Color.orange).opacity(0.15))
          Image(systemName: off ? "checkmark.shield.fill" : "apple.intelligence")
            .font(.system(size: 24))
            .foregroundStyle(off ? Color.green : Color.orange)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(off ? "Apple Intelligence is off" : "Apple Intelligence is on")
            .font(.title2.weight(.bold))
          Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      if !off && model.modelTotal > 0, let disk = DiskSize.total {
        ProgressView(value: Double(model.modelTotal), total: Double(max(disk, model.modelTotal)))
          .tint(.orange)
          .accessibilityLabel("\(Term.size(model.modelTotal)) of models out of \(Term.size(disk)) of storage")
      }
      HStack(spacing: 10) {
        if off {
          if model.modelTotal > 0 {
            Button("Delete the Leftover Models…") { model.deleteLeftoverModels() }
              .buttonStyle(.borderedProminent)
          }
          Button("Change What's Kept On") { model.page = .intelligence }
        } else {
          Button("Turn Off with Recommended Settings…") {
            model.choose(.recommended)
            model.reviewing = true
          }
          .buttonStyle(.borderedProminent)
          Button("Choose What to Turn Off") { model.page = .intelligence }
          Text("You'll see every change first.").font(.callout).foregroundStyle(.secondary)
        }
      }
      .controlSize(.large)
    }
    .padding(20)
    .card()
  }

  var subtitle: String {
    if model.loadingModels { return "Checking how much space its models take…" }
    if off {
      if model.modelTotal > 0 { return "\(Term.size(model.modelTotal)) of models are still on disk. macOS won't download more." }
      if let kept = model.currentAI, !kept.isEmpty { return "\(kept.count) feature\(kept.count == 1 ? " is" : "s are") kept on. Everything else is off and its models are gone." }
      return "Its models are gone and macOS won't download them again."
    }
    if model.modelTotal > 0 { return "Its models take \(Term.size(model.modelTotal)) on this Mac, whether you use them or not." }
    return "Its features are on. RemoveMacAI can turn off the ones you don't use."
  }
}

struct StatTile: View {
  let title: String
  let value: String
  let link: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        Text(value).font(.title2.weight(.bold)).monospacedDigit()
        Text(link).font(.callout).foregroundStyle(.tint)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .card()
  }
}

enum DiskSize {
  /// The capacity of the startup disk.
  static var total: Int64? {
    let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
    return values?.volumeTotalCapacity.map(Int64.init)
  }
}

extension View {
  /// A grouped-box background that matches System Settings.
  func card() -> some View {
    background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
  }
}

// MARK: - Apple Intelligence

struct IntelligenceView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Form {
      Section {
        Toggle(isOn: $model.aiOff) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Turn off Apple Intelligence").font(.headline)
            Text("Switches off the features below, deletes their models and stops macOS downloading them again. Turn it back on any time and macOS re-downloads what it needs.")
              .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
        }
        .toggleStyle(.switch)
      } footer: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Footer("macOS asks you to install a configuration profile for this, and Undo puts everything back. This part builds on pared by 4evy, which first mapped Apple's asset service and model sets.")
          InfoButton(title: Explain.profile.0, text: Explain.profile.1)
        }
      }

      Section {
        ForEach(Catalog.availableFeatures, id: \.id) { feature in
          Toggle(isOn: Binding(
            get: { model.aiKept.contains(feature.id) },
            set: { if $0 { model.aiKept.insert(feature.id) } else { model.aiKept.remove(feature.id) } }
          )) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(feature.title)
                Text(stateText(feature.id)).font(.caption).foregroundStyle(.secondary)
              }
              if let blurb = FeatureBlurbs.text[feature.id] {
                Text(blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .disabled(!model.aiOff)
        }
      } header: {
        HStack {
          Text("Keep anything you use")
          Spacer()
          if model.aiOff { Text("Switch on to keep").font(.caption).foregroundStyle(.secondary).textCase(nil) }
        }
      } footer: {
        Footer("A kept feature keeps the models it needs, so less space comes back.")
      }

      Section {
        if model.loadingModels {
          HStack { ProgressView().controlSize(.small); Text("Asking Apple's asset service…").foregroundStyle(.secondary) }
        } else if !model.modelsAvailable {
          Text("Apple's asset service didn't answer, so the sizes are unknown.").foregroundStyle(.secondary)
        } else {
          ForEach(Catalog.availableModelSets, id: \.name) { set in
            LabeledContent(set.title) {
              let bytes = model.modelBytes[set.name] ?? 0
              Text(bytes > 0 ? Term.size(bytes) : "None").foregroundStyle(bytes > 0 ? .primary : .secondary)
            }
          }
          LabeledContent("Total") { Text(Term.size(model.modelTotal)).fontWeight(.semibold) }
          if model.currentAI != nil && model.modelTotal > 0 {
            HStack {
              Text("Apple Intelligence is off, but these models are still on disk.").foregroundStyle(.secondary)
              Spacer()
              Button("Delete Models") { model.deleteLeftoverModels() }
            }
          }
        }
      } header: {
        HStack(spacing: 6) {
          Text("Models on disk")
          InfoButton(title: Explain.models.0, text: Explain.models.1)
        }
      } footer: {
        Footer("macOS deletes the files on its own schedule, so Storage settings can count them for a while after removal.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Apple Intelligence")
  }

  func stateText(_ id: String) -> String {
    switch model.featureStates[id] {
    case .lockedOff?: return "· Off, kept off by the profile"
    case .off?: return "· Off"
    case .on?: return "· On"
    default: return model.loadingModels ? "· Checking…" : ""
    }
  }
}

// MARK: - Tweak groups

struct TweakGroupView: View {
  @Environment(AppModel.self) private var model
  let group: TweakGroup

  var tweaks: [Tweak] { Tweaks.all.filter { $0.group == group } }

  var body: some View {
    Form {
      Section {
        ForEach(tweaks) { TweakRow(tweak: $0) }
      } header: {
        Text(group.summary).font(.body).foregroundStyle(.secondary).textCase(nil)
      } footer: {
        if tweaks.contains(where: \.inProfile) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Footer("Settings with a lock are kept in place by the RemoveMacAI profile, which you install in System Settings.")
            InfoButton(title: Explain.locked.0, text: Explain.locked.1)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(group.title)
    .toolbar {
      ToolbarItem {
        Menu {
          Button("Select All") { for t in tweaks where t.supported { model.toggle(t, true) } }
          Button("Select Recommended") {
            for t in tweaks {
              let recommended = t.presets.contains(.recommended)
              if model.state(t) == .partial && !recommended {
                model.leave(t)
              } else {
                model.toggle(t, recommended || model.state(t) == .applied)
              }
            }
          }
          Button("Deselect All") { for t in tweaks { model.toggle(t, false) } }
        } label: {
          Label("Select", systemImage: "checklist")
        }
      }
    }
  }
}

struct TweakRow: View {
  @Environment(AppModel.self) private var model
  let tweak: Tweak

  var body: some View {
    let state = model.state(tweak)
    let wanted = model.isOn(tweak)
    Toggle(isOn: Binding(get: { wanted }, set: { model.toggle(tweak, $0) })) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(tweak.title)
          if tweak.inProfile {
            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
              .help("Kept in place by the RemoveMacAI profile")
          }
          if let note = pendingNote(state: state, wanted: wanted, undoes: model.undoes(tweak)) {
            Text(note).font(.caption.weight(.medium)).foregroundStyle(.tint)
          }
        }
        Text(tweak.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if let caveat = tweak.caveat {
          Label(caveat, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
        if state == .managed {
          Text("Managed by another profile on this Mac.").font(.caption).foregroundStyle(.secondary)
        } else if state == .unsupported {
          Text("Needs macOS \(tweak.since.0).\(tweak.since.1) or newer.").font(.caption).foregroundStyle(.secondary)
        } else if state == .partial {
          Text("Partly applied. It stays as it is unless you switch it.").font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 2)
    }
    .toggleStyle(.switch)
    .disabled(state == .managed || state == .unsupported)
  }

  func pendingNote(state: TweakState, wanted: Bool, undoes: Bool) -> String? {
    if wanted && state != .applied { return "Applies on review" }
    if undoes { return "Undoes on review" }
    return nil
  }
}

// MARK: - Background items

struct BackgroundView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Form {
      Section {
        if model.background.isEmpty {
          Text("No background items from other apps.").foregroundStyle(.secondary)
        }
        ForEach(model.background) { item in
          Toggle(isOn: Binding(
            get: { !model.backgroundOff.contains(item.id) },
            set: { model.setBackground(item, off: !$0) }
          )) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(item.owner)
                if item.system {
                  Text("All users").font(.caption2.weight(.medium)).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
                }
              }
              Text(item.label).font(.caption.monospaced()).foregroundStyle(.secondary)
              Text(item.program).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
              if let warning = item.warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
              }
            }
          }
          .toggleStyle(.switch)
          .disabled(model.backgroundBusy)
        }
      } header: {
        Text("Updaters, helpers and agents other apps installed. They run whether or not their app is open. Switching one off takes effect at once. Updaters are safe to switch off; a helper can be what makes its app work, such as a VPN or Docker.")
          .font(.body).foregroundStyle(.secondary).textCase(nil)
      } footer: {
        Footer("Items marked All users ask for your password. Apple's own background services are protected by System Integrity Protection, so RemoveMacAI leaves them alone.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Background Items")
    .toolbar {
      ToolbarItem {
        Button { model.loadBackground() } label: { Label("Reload", systemImage: "arrow.clockwise") }
      }
    }
  }
}

// MARK: - Storage

struct StorageView: View {
  @Environment(AppModel.self) private var model
  @State private var confirming = false

  /// Selected items that are deleted right away instead of going to the Trash.
  var permanentChosen: [String] {
    model.storage.filter { model.storageChosen.contains($0.id) && $0.permanent }.map(\.title)
  }

  var body: some View {
    Form {
      if !model.scanned {
        Section {
          HStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.title).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
              Text("Find space you can get back").font(.headline)
              Text("Looks for old installers, aerial videos, Xcode leftovers, app caches and Time Machine snapshots. Nothing moves until you choose.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.scanning { ProgressView().controlSize(.small) } else { Button("Scan") { model.scan() } }
          }
          .padding(.vertical, 4)
        }
      } else {
        Section {
          if model.storage.isEmpty {
            Text("Nothing to clean up.").foregroundStyle(.secondary)
          }
          ForEach(model.storage) { item in
            HStack(alignment: .top, spacing: 10) {
              Toggle("", isOn: Binding(
                get: { model.storageChosen.contains(item.id) },
                set: { if $0 { model.storageChosen.insert(item.id) } else { model.storageChosen.remove(item.id) } }
              ))
              .toggleStyle(.checkbox)
              .labelsHidden()
              VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let caveat = item.caveat {
                  Label(caveat, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              Text(item.kind == .snapshots ? "\(item.count) snapshot\(item.count == 1 ? "" : "s")" : Term.size(item.bytes))
                .monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
          }
        } header: {
          HStack {
            Text("Files go to the Trash, so they aren't gone until you empty it. Simulators and snapshots are deleted right away.").textCase(nil)
            Spacer()
            if model.scanning { ProgressView().controlSize(.small) } else { Button("Scan Again") { model.scan() }.buttonStyle(.link) }
          }
        }
        Section {
          HStack {
            if let message = model.cleanMessage {
              Text(message).foregroundStyle(.secondary)
            } else {
              Text(model.storageChosen.isEmpty ? "Nothing selected" : "Selected: \(Term.size(model.chosenBytes))").monospacedDigit()
            }
            Spacer()
            if model.cleaning { ProgressView().controlSize(.small) }
            Button(permanentChosen.isEmpty ? "Move to Trash…" : "Remove…") { confirming = true }
              .buttonStyle(.borderedProminent)
              .disabled(model.storageChosen.isEmpty || model.cleaning)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Storage")
    .confirmationDialog(
      permanentChosen.isEmpty ? "Move the selected items to the Trash?" : "Remove the selected items?",
      isPresented: $confirming
    ) {
      Button(permanentChosen.isEmpty ? "Move to Trash" : "Remove") { model.clean() }
    } message: {
      Text("About \(Term.size(model.chosenBytes)). Items only an administrator can move ask for your password."
        + (permanentChosen.isEmpty ? "" : " \(permanentChosen.joined(separator: " and ")) are deleted right away, not moved to the Trash."))
    }
  }
}

// MARK: - Undo

struct ChangesView: View {
  @Environment(AppModel.self) private var model
  @State private var confirming = false

  var body: some View {
    Form {
      Section("Profile") {
        if model.snapshot.profile.on {
          LabeledContent("RemoveMacAI profile", value: "Installed")
          if model.currentAI != nil { Label("Apple Intelligence off", systemImage: "apple.intelligence") }
          ForEach(model.snapshot.profile.tweaks.sorted(), id: \.self) { id in
            Label(Tweaks.tweak(id)?.title ?? id, systemImage: "lock.fill")
          }
        } else {
          Text("Not installed.").foregroundStyle(.secondary)
        }
      }
      Section("Other changes") {
        let entries = model.journal.entries.sorted { $0.value.date > $1.value.date }
        if entries.isEmpty {
          Text("None.").foregroundStyle(.secondary)
        }
        ForEach(entries, id: \.key) { key, entry in
          LabeledContent {
            Text(entry.date, style: .date).foregroundStyle(.secondary)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(title(entry.tweak))
              Text(key).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
          }
        }
      }
      Section {
        HStack {
          Text("Puts every setting back as it was before RemoveMacAI changed it, and removes the profile.")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Undo Everything…", role: .destructive) { confirming = true }
            .disabled(!model.snapshot.profile.on && model.journal.entries.isEmpty)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Undo")
    .confirmationDialog("Undo everything RemoveMacAI changed?", isPresented: $confirming) {
      Button("Undo Everything", role: .destructive) { model.undoEverything() }
    } message: {
      Text("macOS asks you to remove the profile in System Settings. Deleted models download again when a feature needs them, and files in the Trash stay there.")
    }
  }

  func title(_ id: String) -> String {
    if let t = Tweaks.tweak(id) { return t.title }
    if let item = model.background.first(where: { $0.id == id }) { return "Background item: \(item.owner)" }
    return id
  }
}

struct Footer: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// What each Apple Intelligence feature does, in a line, so people know what
/// they keep or lose.
enum FeatureBlurbs {
  static let text: [String: String] = [
    "siri": "The voice assistant. Keep it and basic Siri still works without the big models.",
    "chatgpt": "Lets Siri and Writing Tools hand requests to ChatGPT.",
    "writing-tools": "Rewrites, proofreads and summarizes text you select.",
    "genmoji": "Makes new emoji from a description.",
    "image-playground": "Generates pictures from a prompt.",
    "mail": "Summarizes emails and suggests replies in Mail.",
    "notification-summaries": "Condenses a stack of notifications into one line.",
    "messages-summaries": "Summarizes long conversations in Messages.",
    "safari-summaries": "Summarizes web pages in Safari.",
    "notes-summaries": "Summarizes recordings and transcripts in Notes.",
    "inline-predictions": "Suggests the rest of a word or sentence as you type.",
    "spatial-photos": "Turns flat photos into 3D spatial scenes.",
    "photos-clean-up": "Removes objects from photos in Photos.",
    "xcode-completion": "Predicts code as you type in Xcode.",
  ]
}
