import Foundation

let usage = """
  RemoveMacAI \(version)
  Debloats macOS: turns Apple Intelligence off, deletes its models, and turns
  off analytics, ads and the rest. Every change can be undone.

  Apple Intelligence
    removemacai                 show what is on, then turn it off (asks first)
    removemacai status          show what is on and how much space the models take
    removemacai off [options]   turn it off without the overview
        --keep a,b              leave these features on (names: removemacai features)
        --dry-run               show what would change, change nothing
        --yes                   do not ask
    removemacai on              turn Apple Intelligence back on, keep the other tweaks
    removemacai features        list the feature names

  Debloat
    removemacai tweaks [--json]           list every tweak and whether it is applied
    removemacai apply <names> [options]   apply tweaks
        --preset recommended|privacy      apply a preset, Apple Intelligence off included
        --dry-run, --yes
    removemacai undo <names>              undo tweaks
    removemacai background [off|on <labels>]
                                          other apps' background items
    removemacai clean [<names>]           show space to get back, move some to the Trash
    removemacai export <file.mobileconfig> [--preset p] [<names>] [--keep a,b] [--no-ai]
                                          write the profile for an MDM

    removemacai revert          undo everything RemoveMacAI changed
    removemacai app             open the RemoveMacAI app

  """

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
  guard let i = args.firstIndex(of: name) else { return false }
  args.remove(at: i)
  return true
}
func option(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name) else { return nil }
  guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
    Term.fail(name == "--keep" ? "--keep needs feature names" : "\(name) needs a value")
  }
  let value = args[i + 1]
  args.removeSubrange(i...(i + 1))
  return value
}
func presetOption() -> Preset? {
  guard let name = option("--preset") else { return nil }
  guard let preset = Preset(rawValue: name) else {
    Term.fail("there is no preset called \"\(name)\". Use recommended or privacy")
  }
  return preset
}

// Opened from Finder: the app. With arguments, or from a bare binary: the CLI.
if args.isEmpty && Bundle.main.bundleURL.pathExtension == "app" || args.first == "app" {
  guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
    Term.fail("RemoveMacAI needs macOS 26 or newer")
  }
  Shell.inApp = true
  RemoveMacAIApp.main()
  exit(0)
}

guard args.first == "selftest" || ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
  Term.fail("RemoveMacAI needs macOS 26 or newer")
}

switch args.first {
case "status":
  Commands.status()
case "off", nil:
  if !args.isEmpty { args.removeFirst() }
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let extra = args.first { Term.fail("unknown option \(extra)") }
  exit(Commands.off(keep: keep, dryRun: dryRun, yes: yes) ? 0 : 1)
case "revert":
  Commands.revert()
case "on":
  Commands.on()
case "features":
  args.removeFirst()
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  Commands.features()
case "tweaks":
  args.removeFirst()
  let json = flag("--json")
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  TweakCommands.list(json: json)
case "apply", "undo":
  let command = args.removeFirst()
  let preset = presetOption()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let bad = args.first(where: { $0.hasPrefix("-") }) { Term.fail("unknown option \(bad)") }
  let ok = command == "apply"
    ? TweakCommands.apply(ids: args, preset: preset, dryRun: dryRun, yes: yes)
    : TweakCommands.undo(ids: args, dryRun: dryRun, yes: yes)
  exit(ok ? 0 : 1)
case "background":
  args.removeFirst()
  let yes = flag("--yes") || flag("-y")
  exit(TweakCommands.background(args, yes: yes) ? 0 : 1)
case "clean":
  args.removeFirst()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let bad = args.first(where: { $0.hasPrefix("-") }) { Term.fail("unknown option \(bad)") }
  exit(TweakCommands.clean(ids: args, dryRun: dryRun, yes: yes) ? 0 : 1)
case "export":
  args.removeFirst()
  let preset = presetOption()
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty })
  let noAI = flag("--no-ai")
  guard let path = args.first else { Term.fail("name the file to write, for example: removemacai export RemoveMacAI.mobileconfig") }
  TweakCommands.export(path: path, ids: Array(args.dropFirst()), preset: preset, keepAI: keep, noAI: noAI)
case "selftest":
  exit(selfTest() ? 0 : 1)
case "--version", "-v", "version":
  print(version)
case "help", "--help", "-h":
  print(usage, terminator: "")
default:
  print(usage, terminator: "")
  exit(1)
}
