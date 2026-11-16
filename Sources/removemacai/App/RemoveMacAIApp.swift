import AppKit
import SwiftUI

struct RemoveMacAIApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @State private var model = AppModel()

  var body: some Scene {
    Window("RemoveMacAI", id: "main") {
      ContentView()
        .environment(model)
        .frame(minWidth: 860, minHeight: 600)
    }
    .defaultSize(width: 1000, height: 700)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(replacing: .appInfo) {
        Button("About RemoveMacAI") { AppDelegate.showAbout() }
        Button("Check for Updates…") { AppDelegate.checkForUpdates() }
      }
      CommandGroup(after: .appSettings) {
        Button("Install Command Line Tool…") { AppDelegate.installCommandLineTool() }
      }
      CommandGroup(after: .toolbar) {
        Button("Reload") { model.reload(resetChoices: true) }.keyboardShortcut("r")
      }
      CommandGroup(replacing: .help) {
        Button("How RemoveMacAI Works") { model.openWelcome() }
        Divider()
        Link("RemoveMacAI on GitHub", destination: URL(string: "https://github.com/omlahore/RemoveMacAI")!)
        Link("Report a Problem", destination: URL(string: "https://github.com/omlahore/RemoveMacAI/issues/new/choose")!)
        Divider()
        Link("Sponsor RemoveMacAI", destination: URL(string: "https://github.com/sponsors/omlahore")!)
      }
    }
  }
}

// Inside an NSObject subclass `version` resolves to NSObject.version(), not this string.
private let appVersion = version

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // A bare binary run from Terminal has no bundle, so it must ask to be a real app.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // Started outside Launch Services (Homebrew, Terminal), SwiftUI never opens the window on its own.
    DispatchQueue.main.async {
      guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
      let reopen = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
        targetDescriptor: NSAppleEventDescriptor(processIdentifier: getpid()),
        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
      _ = try? reopen.sendEvent(options: [.noReply], timeout: 1)
    }
    #if DEBUG
      if let dir = ProcessInfo.processInfo.environment["REMOVEMACAI_SNAPSHOTS"] { Snapshots.run(into: dir) }
    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  /// Asks GitHub for the latest release, only when chosen from the menu.
  static func checkForUpdates() {
    Task { @MainActor in
      let alert = NSAlert()
      switch await Updates.latest() {
      case .success(let release) where Updates.isNewer(release.version, than: appVersion):
        alert.messageText = String(localized: "RemoveMacAI \(release.version) is available.")
        alert.informativeText = String(localized: "You have \(appVersion). Download the new version from GitHub and replace this app with it.")
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
        return
      case .success:
        alert.messageText = String(localized: "RemoveMacAI is up to date.")
        alert.informativeText = String(localized: "You have \(appVersion), the latest version.")
      case .failure(let error):
        alert.messageText = String(localized: "RemoveMacAI couldn't check for updates.")
        alert.informativeText = error.localizedDescription
      }
      alert.runModal()
    }
  }

  /// Links the app's binary into /usr/local/bin, so the app from the zip gets
  /// the removemacai command the installer and Homebrew give. Asks first, and
  /// never replaces a file there that isn't a link.
  static func installCommandLineTool() {
    guard let binary = Bundle.main.executablePath else { return }
    let path = CommandLineTool.path
    let fm = FileManager.default
    if let existing = try? fm.destinationOfSymbolicLink(atPath: path) {
      if existing == binary {
        return message(String(localized: "The removemacai command is already installed."),
          String(localized: "Open Terminal and run removemacai status."))
      }
    } else if fm.fileExists(atPath: path) {
      return message(String(localized: "Something else is already at \(path)."),
        String(localized: "RemoveMacAI left it as it is. Remove it first, then try again."))
    }
    let confirm = NSAlert()
    confirm.messageText = String(localized: "Install the removemacai command?")
    confirm.informativeText = String(localized: "This links \(path) to this app, so you can run removemacai in Terminal. If you move or delete the app, the command stops working. macOS asks for your password.")
    confirm.addButton(withTitle: String(localized: "Install"))
    confirm.addButton(withTitle: String(localized: "Cancel"))
    guard confirm.runModal() == .alertFirstButtonReturn else { return }
    let result = CommandLineTool.link(
      to: binary, prompt: String(localized: "RemoveMacAI needs your password to install the removemacai command."))
    if result.ok {
      message(String(localized: "The removemacai command is installed."),
        String(localized: "Open a new Terminal window and run removemacai status."))
    } else {
      message(String(localized: "The removemacai command wasn't installed."), localizedMessage(Shell.adminError(result)))
    }
  }

  private static func message(_ title: String, _ text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    alert.runModal()
  }

  static func showAbout() {
    let credits = NSMutableAttributedString(
      string: String(localized: "Debloats macOS and can undo every change.\n\nThe Apple Intelligence part builds on pared by 4evy, which first mapped Apple's asset service and model sets."),
      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "RemoveMacAI",
      .applicationVersion: appVersion,
      .version: "",
      .credits: credits,
    ])
  }
}
