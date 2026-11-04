#if DEBUG
  import AppKit

  /// Debug builds only: renders each page to PNG for checking the layout
  /// without screen-recording permission. REMOVEMACAI_SNAPSHOTS=<folder>.
  @MainActor
  enum Snapshots {
    static func run(into dir: String) {
      let pages: [(String, Page)] =
        [("overview", .overview), ("intelligence", .intelligence)]
        + TweakGroup.allCases.map { ($0.rawValue, Page.group($0)) }
        + [("background", .background), ("storage", .storage), ("changes", .changes)]
      if let look = ProcessInfo.processInfo.environment["REMOVEMACAI_APPEARANCE"] {
        NSApp.appearance = NSAppearance(named: look == "light" ? .aqua : .darkAqua)
      }
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard let model = AppModel.shared else { return }
        model.showingWelcome = false
        model.showMoreTools = false
        try? await Task.sleep(nanoseconds: 800_000_000)
        save("overview-lite", dir)
        model.showMoreTools = true
        model.scan()
        while model.scanning || !model.scanned { try? await Task.sleep(nanoseconds: 300_000_000) }
        for (name, page) in pages {
          model.page = page
          try? await Task.sleep(nanoseconds: 1_200_000_000)
          save(name, dir)
        }
        if ProcessInfo.processInfo.environment["REMOVEMACAI_SNAPSHOTS_WELCOME"] != nil {
          for i in 0..<3 {
            model.welcomePage = i
            model.showingWelcome = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            save("welcome-\(i + 1)", dir)
          }
          model.showingWelcome = false
          try? await Task.sleep(nanoseconds: 800_000_000)
        }
        if ProcessInfo.processInfo.environment["REMOVEMACAI_SNAPSHOTS_REVIEW"] != nil {
          model.page = .overview
          model.choose(.privacy)
          // Tweaks to show as pending, so the review sheet has something to list on a debloated Mac.
          for id in (ProcessInfo.processInfo.environment["REMOVEMACAI_SNAPSHOTS_PENDING"] ?? "").split(separator: ",") {
            if let t = Tweaks.tweak(String(id)) { model.toggle(t, true) }
          }
          try? await Task.sleep(nanoseconds: 800_000_000)
          save("pending", dir)
          model.reviewing = true
          try? await Task.sleep(nanoseconds: 4_000_000_000)
          save("review", dir)
          model.reviewing = false
          model.run = .approveProfile(remove: false)
          try? await Task.sleep(nanoseconds: 1_200_000_000)
          save("approve", dir)
          model.run = .finished(problems: [], freed: 6_400_000_000)
          try? await Task.sleep(nanoseconds: 1_200_000_000)
          save("finished", dir)
          model.run = nil
          model.discard()
        }
        if let ids = ProcessInfo.processInfo.environment["REMOVEMACAI_TEST_APPLY"] {
          let tweaks = ids.split(separator: ",").compactMap { Tweaks.tweak(String($0)) }
          for on in [true, false] {
            for t in tweaks { model.toggle(t, on) }
            model.apply()
            while true {
              if case .finished? = model.run { break }
              try? await Task.sleep(nanoseconds: 300_000_000)
            }
            save(on ? "applied" : "reverted", dir)
            let states = tweaks.map { "\($0.id)=\(model.state($0))" }.joined(separator: " ")
            print((on ? "applied: " : "reverted: ") + states + " run=\(String(describing: model.run!))")
            model.dismissRun()
          }
        }
        NSApp.terminate(nil)
      }
    }

    typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    static let createImage: CreateImage? = {
      guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
      return unsafeBitCast(sym, to: CreateImage.self)
    }()

    /// The window as the compositor draws it, glass and all. An app may
    /// capture its own windows without screen-recording permission.
    static func capture(_ window: NSWindow) -> NSBitmapImageRep? {
      // optionIncludingWindow = 8; boundsIgnoreFraming = 1, bestResolution = 8
      guard let image = createImage?(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { return nil }
      return NSBitmapImageRep(cgImage: image)
    }

    static func save(_ name: String, _ dir: String) {
      for (i, window) in NSApp.windows.enumerated() where window.isVisible {
        if ProcessInfo.processInfo.environment["REMOVEMACAI_REAL"] != nil, let rep = capture(window) {
          let file = "\(dir)/\(name)\(i == 0 ? "" : "-\(i)").png"
          try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
          continue
        }
        guard let view = window.contentView?.superview ?? window.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { continue }
        view.cacheDisplay(in: view.bounds, to: rep)
        let file = "\(dir)/\(name)\(i == 0 ? "" : "-\(i)").png"
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
      }
    }
  }
#endif
