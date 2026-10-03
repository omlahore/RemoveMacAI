import Foundation

extension Commands {
  /// Everything off would act on, measured from more than one source, so a
  /// wrong number from one of them shows. Reads only; changes nothing.
  static func scan(keep: Set<String>) {
    header()
    let inventory = Models.inventory()
    let sets = Set(Catalog.setsToRemove(keeping: keep))

    print(Term.bold("Model sets"))
    if inventory == nil {
      print(Term.yellow("  ! ") + "Apple's asset service did not share its inventory, so sizes are unknown.")
    }
    for set in Catalog.modelSets {
      print("  " + Term.bold(set.title) + Term.dim("  \(set.name)"))
      let tracked = inventory?.bytes[set.assetType] ?? 0
      let count = inventory?.assets[set.assetType] ?? 0
      print("    " + Term.pad("Tracked by macOS", 22)
        + (count > 0 ? Term.yellow(Term.size(tracked)) + Term.dim(" in \(count) assets") : Term.dim("nothing")))
      let folder: String
      if !Models.folderExists(set.name) {
        folder = Term.dim("none")
      } else if let bytes = Models.folderBytes(set.name) {
        folder = bytes > 0 ? Term.yellow(Term.size(bytes)) : Term.dim("empty")
      } else {
        folder = Term.yellow("present") + Term.dim(geteuid() == 0
          ? ", protected by System Integrity Protection, readable only from Recovery"
          : ", size hidden by macOS (try: sudo removemacai scan)")
      }
      print("    " + Term.pad("Folder on disk", 22) + folder)
      let clients = inventory?.subscribers[set.name].map { $0.sorted() } ?? []
      let usages = inventory?.usages[set.name] ?? 0
      print("    " + Term.pad("Asked for by", 22)
        + (clients.isEmpty ? Term.dim("nobody") : clients.joined(separator: ", "))
        + (usages > 0 ? Term.dim("  (\(usages) active usage\(usages == 1 ? "" : "s"))") : ""))
      let blocked = Settings.isForcedString(Profile.downloadDomain, Profile.downloadKey(set))
      print("    " + Term.pad("Downloads", 22) + (blocked ? Term.green("blocked by profile") : "allowed"))
      let action: String
      if !sets.contains(set.name) {
        action = Term.dim("keep (a kept feature needs it)")
      } else if Models.present(set.name) {
        action = "ask macOS to delete it"
          + (clients.isEmpty ? "" : Term.yellow(", also removes it for " + clients.joined(separator: ", ")))
      } else {
        action = Term.dim("nothing to delete")
      }
      print("    " + Term.pad("off would", 22) + action)
    }

    print()
    print(Term.bold("Disk"))
    let disk = Disk.capacity()
    print("  " + Term.pad("Free", 24) + Term.size(disk.free))
    print("  " + Term.pad("Purgeable", 24) + Term.size(disk.purgeable)
      + Term.dim("  macOS frees this itself when space runs low; released models land here"))
    print()
    print(Term.dim("Nothing was changed."))
  }
}

enum Disk {
  static func capacity() -> (free: Int64, purgeable: Int64) {
    let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
    let v = try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: keys)
    let free = Int64(v?.volumeAvailableCapacity ?? 0)
    let important = v?.volumeAvailableCapacityForImportantUsage ?? free
    return (free, max(0, important - free))
  }
}
