import Foundation

let usage = """
  RemoveMacAI \(version)
  Turns Apple Intelligence off and deletes its models. Optional tweaks turn off
  analytics, ads and the rest. Every change can be undone.

  Apple Intelligence
    removemacai                 show what is on, then turn it off (asks first)
    removemacai status          show what is on and how much space the models take
    removemacai off [options]   turn it off without the overview
        --keep a,b              leave these features on (names: removemacai features)
        --dry-run               show what would change, change nothing
        --yes                   do not ask
    removemacai on              turn Apple Intelligence back on, keep the other tweaks
    removemacai features [--json]  list the feature names

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
        --for iphone|ipad                 write an iPhone (ios) or iPad (ipados) profile instead.
                                          It turns Apple Intelligence off. Models stay on the device.

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
func unknownOption(in args: [String]) -> String? {
  args.first(where: { $0.hasPrefix("-") })
}
let knownCommands = [
  "status", "off", "on", "revert", "features", "tweaks", "apply", "undo",
  "background", "clean", "export", "selftest", "app", "help", "version",
]
func commandDistance(_ a: String, _ b: String) -> Int {
  let a = Array(a), b = Array(b)
  var row = Array(0...b.count)
  for (i, ca) in a.enumerated() {
    var next = [i + 1] + Array(repeating: 0, count: b.count)
    for (j, cb) in b.enumerated() {
      next[j + 1] = ca == cb ? row[j] : min(row[j], min(row[j + 1], next[j])) + 1
    }
    row = next
  }
  return row[b.count]
}
func suggestCommand(for name: String) -> String? {
  var closest: String?
  var closestDistance = Int.max
  for command in knownCommands {
    let distance = commandDistance(name, command)
    if distance < closestDistance { closest = command; closestDistance = distance }
  }
  return closestDistance <= 2 ? closest : nil
}
func unknownCommandMessage(_ name: String) -> String {
  var message = "unknown command \"\(name)\""
  if let hint = suggestCommand(for: name) { message += ". Did you mean \"\(hint)\"?" }
  return message
}
func mobileDeviceOption() -> Mobile.Device? {
  guard let name = option("--for") else { return nil }
  guard let device = Mobile.Device(argument: name) else {
    Term.fail("unknown device \"\(name)\". Use iphone, ios, ipad, or ipados")
  }
  return device
}

func presetOption() -> Preset? {
  guard let name = option("--preset") else { return nil }
  guard let preset = Preset(rawValue: name) else {
    Term.fail("there is no preset called \"\(name)\". Use recommended or privacy")
  }
  return preset
}

// Apple Intelligence starts at macOS 15.1.
let supportedOS = ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 15, minorVersion: 1, patchVersion: 0))

// Opened from Finder: the app. With arguments, or from a bare binary: the CLI.
if args.isEmpty && Bundle.main.bundleURL.pathExtension == "app" || args.first == "app" {
  guard supportedOS else { Term.fail("RemoveMacAI needs macOS 15.1 or newer") }
  Shell.inApp = true
  RemoveMacAIApp.main()
  exit(0)
}

guard args.first == "selftest" || supportedOS else { Term.fail("RemoveMacAI needs macOS 15.1 or newer") }

switch args.first {
case "status":
  args.removeFirst()
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  Commands.status()
case "off", nil:
  if !args.isEmpty { args.removeFirst() }
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let extra = args.first { Term.fail("unknown option \(extra)") }
  exit(Commands.off(keep: keep, dryRun: dryRun, yes: yes) ? 0 : 1)
case "revert":
  args.removeFirst()
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  Commands.revert()
case "on":
  args.removeFirst()
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  Commands.on()
case "features":
  args.removeFirst()
  let json = flag("--json")
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  Commands.features(json: json)
case "tweaks":
  args.removeFirst()
  let json = flag("--json")
  if let extra = args.first { Term.fail("unexpected argument \(extra)") }
  TweakCommands.list(json: json)
case "apply":
  args.removeFirst()
  let preset = presetOption()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let bad = unknownOption(in: args) { Term.fail("unknown option \(bad)") }
  exit(TweakCommands.apply(ids: args, preset: preset, dryRun: dryRun, yes: yes) ? 0 : 1)
case "undo":
  args.removeFirst()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let bad = unknownOption(in: args) { Term.fail("unknown option \(bad)") }
  exit(TweakCommands.undo(ids: args, dryRun: dryRun, yes: yes) ? 0 : 1)
case "background":
  args.removeFirst()
  let yes = flag("--yes") || flag("-y")
  exit(TweakCommands.background(args, yes: yes) ? 0 : 1)
case "clean":
  args.removeFirst()
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let bad = unknownOption(in: args) { Term.fail("unknown option \(bad)") }
  exit(TweakCommands.clean(ids: args, dryRun: dryRun, yes: yes) ? 0 : 1)
case "export":
  args.removeFirst()
  let preset = presetOption()
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty })
  let noAI = flag("--no-ai")
  let device = mobileDeviceOption()
  if let bad = unknownOption(in: args) { Term.fail("unknown option \(bad)") }
  guard let path = args.first else { Term.fail("name the file to write, for example: removemacai export RemoveMacAI.mobileconfig") }
  TweakCommands.export(path: path, ids: Array(args.dropFirst()), preset: preset, keepAI: keep, noAI: noAI, device: device)
case "selftest":
  exit(selfTest() ? 0 : 1)
case "--version", "-v", "version":
  print(version)
case "help", "--help", "-h":
  print(usage, terminator: "")
default:
  if let command = args.first { Term.fail(unknownCommandMessage(command)) }
  print(usage, terminator: "")
  exit(1)
}
