import Foundation

let usage = """
  RemoveMacAI \(version)
  Turns Apple Intelligence off on macOS and deletes its models.

    removemacai                 show what is on, then turn it off (asks first)
    removemacai status          show what is on and how much space the models take
    removemacai scan [--keep a,b]  show what is really on disk and what off would do (changes nothing)
    removemacai off [options]   turn it off without the overview
        --keep a,b              leave these features on (names: removemacai features)
        --dry-run               show what would change, change nothing
        --yes                   do not ask
    removemacai revert          undo everything
    removemacai features        list the feature names

  """

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
  guard let i = args.firstIndex(of: name) else { return false }
  args.remove(at: i)
  return true
}
func option(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  let value = args[i + 1]
  args.removeSubrange(i...(i + 1))
  return value
}

guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
  Term.fail("RemoveMacAI needs macOS 26 or newer")
}

switch args.first {
case "status":
  Commands.status()
case "scan":
  args.removeFirst()
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
  if let extra = args.first { Term.fail("unknown option \(extra)") }
  Commands.scan(keep: keep)
case "off", nil:
  if !args.isEmpty { args.removeFirst() }
  let keep = Set((option("--keep") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
  let dryRun = flag("--dry-run")
  let yes = flag("--yes") || flag("-y")
  if let extra = args.first { Term.fail("unknown option \(extra)") }
  Commands.off(keep: keep, dryRun: dryRun, yes: yes)
case "revert", "on":
  Commands.revert()
case "features":
  Commands.features()
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
