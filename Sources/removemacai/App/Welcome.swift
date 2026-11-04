import SwiftUI

/// The first-run introduction: what the app does and doesn't do, how the
/// profile step works, and where to start. Shown once, and again from
/// Help > How RemoveMacAI Works or the Overview.
struct WelcomeSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var start: Start = .appleIntelligence

  enum Start: CaseIterable, Identifiable {
    case appleIntelligence, recommended, own
    var id: Self { self }
  }

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      Group {
        switch model.welcomePage {
        case 0: intro
        case 1: howItWorks
        default: chooseStart
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.welcomePage == 1 ? .top : .center)
      .padding(.horizontal, 36)
      .padding(.top, 30)
      footer
    }
    .frame(width: 680, height: 600)
    .animation(.easeOut(duration: 0.2), value: model.welcomePage)
  }

  var intro: some View {
    VStack(spacing: 22) {
      VStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable().frame(width: 72, height: 72)
          .accessibilityHidden(true)
        Text("Take Apple Intelligence off your Mac")
          .font(.title.weight(.bold))
          .multilineTextAlignment(.center)
        Text("RemoveMacAI turns off the Apple Intelligence features you don't use, deletes the models they download, and tidies up other things macOS adds. It's free and open source.")
          .font(.body).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 500)
          .fixedSize(horizontal: false, vertical: true)
      }
      Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          PromiseCard(promise: Promises.all[0])
          PromiseCard(promise: Promises.all[1])
        }
        GridRow {
          PromiseCard(promise: Promises.all[2])
          PromiseCard(promise: Promises.all[3])
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  var howItWorks: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(spacing: 6) {
        Text("How it works").font(.title.weight(.bold))
        Text("Three steps, and you can stop at any of them.").foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      HStack(alignment: .top, spacing: 12) {
        stepCard(1, "Choose", "Pick a preset or switch single things off. Each one says what it does.")
        stepCard(2, "Review", "You see the full list and how much space comes back. Nothing has changed yet.")
        stepCard(3, "Approve", "macOS asks you to install a profile in System Settings. Only you can make that click.", highlight: true)
      }
      .fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .top, spacing: 20) {
        SettingsGuide()
          .frame(width: 340)
        VStack(alignment: .leading, spacing: 10) {
          Text("Why does macOS ask for a profile?").font(.headline)
          Text("macOS only lets these settings stay locked through a configuration profile, the same thing schools and companies use to manage their Macs. You can read what's in it before you install it.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Text("Remove it any time in System Settings › General › Device Management, or with Undo in RemoveMacAI.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Button("Watch the demo") { openURL(URL(string: "https://github.com/omlahore/RemoveMacAI#readme")!) }
            .buttonStyle(.link)
        }
        .font(.callout)
      }
    }
  }

  var chooseStart: some View {
    VStack(spacing: 14) {
      VStack(spacing: 6) {
        Text("Where do you want to start?").font(.title.weight(.bold))
        Text("You can change any of this later. Nothing changes until you review it.").foregroundStyle(.secondary)
      }
      .padding(.bottom, 6)
      ForEach(Start.allCases) { option in
        Button { start = option } label: { startRow(option) }
          .buttonStyle(.plain)
          .accessibilityAddTraits(start == option ? .isSelected : [])
      }
    }
  }

  func startRow(_ option: Start) -> some View {
    let selected = start == option
    return HStack(alignment: .top, spacing: 14) {
      Image(systemName: selected ? "largecircle.fill.circle" : "circle")
        .font(.title3)
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title(option)).font(.headline)
          if option == .appleIntelligence {
            Text("Most people").font(.caption.weight(.semibold)).foregroundStyle(.green)
              .padding(.horizontal, 7).padding(.vertical, 2)
              .background(Capsule().fill(Color.green.opacity(0.15)))
          }
        }
        Text(summary(option)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if !detail(option).isEmpty {
          Text(detail(option)).font(.caption).foregroundStyle(.tertiary)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .contentShape(Rectangle())
    .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07)))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
  }

  func title(_ option: Start) -> String {
    switch option {
    case .appleIntelligence: return String(localized: "Just Apple Intelligence")
    case .recommended: return L(Preset.recommended.title)
    case .own: return String(localized: "I'll choose myself")
    }
  }

  func summary(_ option: Start) -> String {
    switch option {
    case .appleIntelligence: return String(localized: "Turn off its features and delete its models. Nothing else on your Mac changes.")
    case .recommended: return L(Preset.recommended.summary)
    case .own: return String(localized: "Start with nothing selected and pick from the sidebar.")
    }
  }

  func detail(_ option: Start) -> String {
    let models = model.modelTotal > 0 ? String(localized: " and \(UISize.of(model.modelTotal)) of models") : ""
    switch option {
    case .appleIntelligence: return model.modelTotal > 0 ? String(localized: "Frees about \(UISize.of(model.modelTotal))") : ""
    case .recommended: return String(localized: "\(Tweaks.preset(.recommended).count) settings") + models
    case .own: return String(localized: "Nothing is selected for you")
    }
  }

  func stepCard(_ n: Int, _ title: LocalizedStringKey, _ text: LocalizedStringKey, highlight: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      StepBadge(number: n)
      Text(title).font(.headline)
      Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 12).fill(highlight ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07)))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlight ? Color.accentColor.opacity(0.5) : .clear))
  }

  var footer: some View {
    HStack {
      if model.welcomePage == 0 {
        Button("Skip") { finish(nil) }
          .keyboardShortcut(.cancelAction)
      } else {
        Button("Back") { model.welcomePage -= 1 }
      }
      Spacer()
      HStack(spacing: 7) {
        ForEach(0..<3) { i in
          Circle().fill(i == model.welcomePage ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 8, height: 8)
        }
      }
      .accessibilityElement()
      .accessibilityLabel("Step \(model.welcomePage + 1) of 3")
      Spacer()
      if model.welcomePage < 2 {
        Button("Continue") { model.welcomePage += 1 }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      } else {
        Button(start == .own ? "Start Choosing" : "Show Me the Changes") { finish(start) }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .controlSize(.large)
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
  }

  func finish(_ choice: Start?) {
    model.closeWelcome()
    switch choice {
    case .appleIntelligence?:
      model.chooseAppleIntelligence()
    case .recommended?:
      model.setMoreTools(true)
      model.choose(.recommended)
    case .own?:
      model.setMoreTools(true)
      model.page = .intelligence
      return
    case nil:
      return
    }
    // A second sheet can't open while this one is still closing.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.reviewing = true }
  }
}
