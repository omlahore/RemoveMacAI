import AppKit
import SwiftUI

struct ContentView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      Sidebar()
        .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    } detail: {
      DetailView(page: model.page ?? .overview)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if model.pendingCount > 0 { PendingBar() }
        }
    }
    .sheet(isPresented: $model.showingWelcome) { WelcomeSheet() }
    .sheet(isPresented: $model.reviewing) { ReviewSheet() }
    .sheet(isPresented: Binding(get: { model.run != nil }, set: { if !$0 { model.dismissRun() } })) {
      RunSheet()
    }
  }
}

struct DetailView: View {
  let page: Page

  var body: some View {
    switch page {
    case .overview: OverviewView()
    case .intelligence: IntelligenceView()
    case .group(let group): TweakGroupView(group: group)
    case .background: BackgroundView()
    case .storage: StorageView()
    case .changes: ChangesView()
    case .settings: SettingsView()
    }
  }
}

// MARK: - Sidebar

struct Sidebar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    List(selection: $model.page) {
      row(.overview)
      Section("Turn Off") {
        row(.intelligence, badge: model.aiPending ? Text("1") : nil)
        ForEach([TweakGroup.privacy, .annoyances, .apps], id: \.self) { group in
          row(.group(group), badge: count(group))
        }
        row(.background)
      }
      Section("Customize") {
        ForEach([TweakGroup.finder, .windows, .typing], id: \.self) { group in
          row(.group(group), badge: count(group))
        }
      }
      Section("Clean Up") {
        row(.storage)
        row(.changes)
      }
      Section("Settings") {
        row(.settings)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Button { model.openWelcome() } label: {
        Label("How RemoveMacAI Works", systemImage: "questionmark.circle")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
    }
  }

  func row(_ page: Page, badge: Text? = nil) -> some View {
    Label(L(page.title), systemImage: page.symbol)
      .badge(badge)
      .tag(page)
  }

  func count(_ group: TweakGroup) -> Text? {
    let c = model.switchedOn(in: group)
    return c.on > 0 ? Text("\(c.on) of \(c.total)") : nil
  }
}

// MARK: - Bottom bar and review

struct PendingBar: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.tint)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.pendingCount == 1 ? "1 change ready" : "\(model.pendingCount) changes ready")
          .font(.callout.weight(.medium))
        Text("Nothing has changed yet. You'll see the full list first.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Discard") { model.discard() }
      Button("Review and Apply…") { model.reviewing = true }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }
}

struct ReviewSheet: View {
  @Environment(AppModel.self) private var model
  @State private var plan: Plan?
  @State private var showCommands = false

  var changeCount: Int {
    guard let plan else { return 0 }
    return plan.apply.count + plan.revert.count + (model.aiPending ? 1 : 0)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        Text(changeCount == 1 ? "Review 1 change" : "Review \(changeCount) changes").font(.title2.weight(.bold))
        if let plan {
          HStack(spacing: 8) {
            if !plan.models.isEmpty, let bytes = model.modelBytes(plan.models), bytes > 0 {
              chip("Frees about \(UISize.of(bytes))", color: .green)
            }
            chip("Undo any time", color: .accentColor)
            if plan.profile.map({ !$0.isEmpty }) ?? false {
              chip("Asks for your password once", color: .secondary)
            }
          }
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 22)
      .padding(.bottom, 14)
      Divider()
      if let plan {
        List {
          if model.aiPending || !plan.models.isEmpty {
            Section("Apple Intelligence") {
              if model.aiPending, let kept = model.targetAI {
                Label(
                  kept.isEmpty
                    ? "Turn off every feature"
                    : kept.count == 1 ? "Turn off everything except 1 kept feature" : "Turn off everything except \(kept.count) kept features",
                  systemImage: "apple.intelligence")
              } else if model.aiPending {
                Label("Turn Apple Intelligence back on. macOS downloads its models again when a feature needs them.", systemImage: "arrow.uturn.backward")
              }
              if !plan.models.isEmpty {
                let bytes = model.modelBytes(plan.models)
                Label {
                  HStack {
                    Text(bytes.map { $0 > 0 ? String(localized: "Delete the models, about \(UISize.of($0))") : L("Ask macOS to finish removing leftover model files") } ?? L("Delete the models"))
                    Spacer()
                    Text("macOS can download them again").font(.caption).foregroundStyle(.secondary)
                  }
                } icon: {
                  Image(systemName: "trash")
                }
              }
            }
          }
          if !plan.apply.isEmpty {
            Section("Turn on or off") {
              ForEach(plan.apply) { t in ChangeRow(tweak: t, adding: true, showCommands: showCommands) }
            }
          }
          if !plan.revert.isEmpty {
            Section("Put back") {
              ForEach(plan.revert) { t in ChangeRow(tweak: t, adding: false, showCommands: showCommands) }
            }
          }
          if let profile = plan.profile {
            Section("What happens when you click Apply") {
              if profile.isEmpty {
                step(1, "Your settings change. This takes a few seconds.")
                step(2, "System Settings opens so you can remove the RemoveMacAI profile. We show you where.")
              } else {
                step(1, "Settings that don't need the profile change right away.")
                step(2, "System Settings opens and you install the RemoveMacAI profile. We show you where.")
                if !plan.models.isEmpty { step(3, "The models are deleted and you get a summary.") }
              }
            }
          }
        }
        .listStyle(.inset)
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      HStack {
        Toggle("Show exact settings", isOn: $showCommands)
          .toggleStyle(.checkbox)
          .help("Shows the command or profile key behind each change")
        Spacer()
        Button("Cancel", role: .cancel) { model.reviewing = false }
          .keyboardShortcut(.cancelAction)
        Button(changeCount == 1 ? "Apply Change" : "Apply \(changeCount) Changes") { model.apply() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(plan?.isEmpty ?? true)
      }
      .controlSize(.large)
      .padding(16)
    }
    .frame(width: 640, height: 600)
    .task {
      let wanted = model.wanted
      let ai = model.targetAI
      let snapshot = model.snapshot
      plan = await Task.detached { Plan.make(wanted: wanted, ai: ai, snapshot: snapshot) }.value
    }
  }

  func chip(_ text: LocalizedStringKey, color: Color) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color == .secondary ? Color.secondary : color)
      .padding(.horizontal, 9).padding(.vertical, 4)
      .background(Capsule().fill(color.opacity(0.13)))
  }

  func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      StepBadge(number: n)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct ChangeRow: View {
  let tweak: Tweak
  let adding: Bool
  var showCommands = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Image(systemName: adding ? "plus.circle.fill" : "arrow.uturn.backward.circle.fill")
          .foregroundStyle(adding ? Color.accentColor : .orange)
        Text(L(tweak.title))
        if tweak.inProfile {
          Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            .help("Kept in place by the RemoveMacAI profile")
        }
        Spacer()
      }
      if showCommands {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(tweak.changes.indices, id: \.self) { i in
            Text(tweak.changes[i].command)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        .padding(.leading, 26)
      }
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Running

struct RunSheet: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Group {
      switch model.run {
      case .working(let text)?:
        VStack(spacing: 16) {
          ProgressView().controlSize(.large)
          Text(L(text)).font(.headline)
          Text("This takes a few seconds.").foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 420)
      case .approveProfile(let remove)?:
        ApproveProfileView(remove: remove)
      case .finished(let problems, let freed)?:
        FinishedView(problems: problems, freed: freed)
      case nil:
        EmptyView()
      }
    }
    .interactiveDismissDisabled()
  }
}

struct ApproveProfileView: View {
  @Environment(AppModel.self) private var model
  let remove: Bool
  @State private var showContents = false
  @State private var showTrouble = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(remove ? "Remove the profile in System Settings" : "One last step in System Settings")
          .font(.title2.weight(.bold))
        Text(remove
          ? "macOS needs you to remove the RemoveMacAI profile yourself. System Settings is open."
          : "macOS needs you to install the RemoveMacAI profile yourself. System Settings is open.")
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .top, spacing: 22) {
        SettingsGuide(remove: remove)
          .frame(width: 360)
        VStack(alignment: .leading, spacing: 14) {
          if remove {
            stepRow(1, "Select RemoveMacAI", "It's under General › Device Management.", active: true)
            stepRow(2, "Click the minus button, then Remove", "Enter your password if macOS asks.", active: false)
          } else {
            stepRow(0, "Settings that don't need the profile are done", nil, active: false, done: true)
            stepRow(2, "Double-click RemoveMacAI under Downloaded", "It's in General › Device Management.", active: true)
            stepRow(3, "Click Install, then enter your password", "macOS may call the profile unsigned. That's normal for a free app that isn't from a company.", active: false)
          }
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(remove ? "Waiting for you to remove it…" : "Waiting for you to install it…").foregroundStyle(.secondary)
          }
          .padding(.top, 2)
        }
      }
      if !remove {
        DisclosureGroup("What's in this profile?", isExpanded: $showContents) {
          VStack(alignment: .leading, spacing: 8) {
            Text("It turns off the Apple Intelligence features you chose, points the model downloads at a closed address on your own Mac so macOS can't fetch them again, and holds the settings marked with a lock. Nothing else.")
              .fixedSize(horizontal: false, vertical: true)
            Button("Show the Profile File") { NSWorkspace.shared.activateFileViewerSelecting([Profile.file]) }
              .buttonStyle(.link)
          }
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.top, 6)
        }
      }
      DisclosureGroup("Something went wrong", isExpanded: $showTrouble) {
        Text(remove
          ? "If System Settings says the profile couldn't be removed, click Cancel here. Your Mac stays as it was, and you can report it on GitHub with Help › Report a Problem."
          : "If System Settings says the profile couldn't be installed, click Cancel here. Your Mac stays as it was, and you can report it on GitHub with Help › Report a Problem.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 6)
      }
      HStack {
        Button("Cancel") { model.cancel() }
        Spacer()
        Button("Show System Settings") { Commands.openProfileSettings() }
          .buttonStyle(.borderedProminent)
      }
      .controlSize(.large)
    }
    .padding(26)
    .frame(width: 760)
    .fixedSize(horizontal: false, vertical: true)
  }

  func stepRow(_ n: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey?, active: Bool, done: Bool = false) -> some View {
    HStack(alignment: .top, spacing: 10) {
      StepBadge(number: n, done: done, active: active)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(done ? .regular : .semibold))
          .foregroundStyle(done ? .secondary : .primary)
          .fixedSize(horizontal: false, vertical: true)
        if let detail {
          Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

struct FinishedView: View {
  @Environment(AppModel.self) private var model
  let problems: [String]
  let freed: Int64?

  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        Circle().fill((problems.isEmpty ? Color.green : Color.orange).opacity(0.15)).frame(width: 64, height: 64)
        Image(systemName: problems.isEmpty ? "checkmark" : "exclamationmark.triangle.fill")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(problems.isEmpty ? Color.green : Color.orange)
      }
      .accessibilityHidden(true)
      Text(problems.isEmpty ? "All done" : "Finished, with a few problems").font(.title2.weight(.bold))
      if let freed, freed > 0 {
        Text("Deleted \(UISize.of(freed)) of Apple Intelligence models. macOS clears the files on its own schedule, so Storage settings may show the old size for a while.")
          .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !problems.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(problems, id: \.self) { Text("• " + localizedMessage($0)).textSelection(.enabled) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 440, maxHeight: 160)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
      }
      if problems.isEmpty {
        VStack(spacing: 6) {
          Text("I make RemoveMacAI by myself in my spare time. If it was useful to you, you can sponsor it on GitHub.")
            .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            .fixedSize(horizontal: false, vertical: true)
          Link("Sponsor on GitHub", destination: URL(string: "https://github.com/sponsors/omlahore")!)
        }
      }
      Text("Changed your mind? Undo in the sidebar puts everything back.")
        .font(.callout).foregroundStyle(.secondary)
      HStack(spacing: 10) {
        Button("See What Changed") {
          model.dismissRun()
          model.page = .changes
        }
        Button("Done") { model.dismissRun() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
      .controlSize(.large)
      .padding(.top, 4)
    }
    .padding(32)
    .frame(width: 520)
  }
}
