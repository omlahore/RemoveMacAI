# Changelog

## 1.2.0-beta.2

- Added Simplified Chinese (简体中文) localization and an in-app language selector (System / English / 简体中文 / Русский) in Settings.

## Unreleased

- Block Music launches is now called Stop Music from opening, even by hand, and its warning says Music won't open at all until you undo it. The old name read as if only AirPods were blocked (#67).

## 1.2.0-beta.1

A beta for macOS 15 (Sequoia). The one-line installer and Homebrew stay on 1.1.4 until it's out of beta.

- RemoveMacAI runs on macOS 15.1 and later, not just 26 and 27 (#45). Apple Intelligence features that a macOS version doesn't have are left out, so Sequoia doesn't list Spatial Photos. Contributed by mojila in #47.
- After a macOS upgrade that adds Apple Intelligence features the profile doesn't cover yet, RemoveMacAI asks you to approve the profile again the next time you run it, instead of saying everything is already off.
- If something goes wrong on Sequoia, open an issue with the output of `removemacai status` and `sw_vers`.

## 1.1.4

- `removemacai undo` with no tweak names now asks you to name them, the way `apply` does, instead of saying nothing needs changing (#57). Contributed by cosmicsid004 in #64.
- Commands no longer accept words and options they don't use, and `--keep` with nothing after it says it needs feature names (#58). Contributed by sean0407 in #62.
- Remove unused Apple apps from the Dock now also takes Image Playground and Journal off the Dock (#63).

## 1.1.3

- After a run finishes with no problems, the app and the command line mention that you can sponsor RemoveMacAI on GitHub. It shows only then, once per run.

## 1.1.2

- When macOS is still using a model set, removal waits and tries again twice before giving up. If it still can't, it says so in plain words and tells you to restart and run RemoveMacAI again, instead of printing the raw lock error (#56, #38).
- Other removal errors show Apple's message instead of the whole error dump.

## 1.1.1

- RemoveMacAI > About RemoveMacAI opens the About window again (#49).
- `removemacai app` opens the app window when you start it from Terminal, which includes the Homebrew install (#51).

## 1.1.0

- A welcome guide opens the first time you run the app. It covers what the app changes and what it leaves alone, shows where to approve the profile in System Settings, and starts you from a preset or from nothing. Help > How RemoveMacAI Works opens it again.
- Every setting describes what it does in plain words. The info buttons explain the profile, the models and the locked settings.
- The review screen lists every change before anything happens and says what Apply does next. Show exact settings lists the commands.
- While you approve the profile, the app shows where to click in System Settings and can show the profile file in Finder so you can read it first.
- The sidebar shows how many settings are on in each section, and Settings changed on the Overview opens the first section that has one (#39, #41).
- The play key setting now says it turns off every media key, so VLC and Spotify lose them too, and it's no longer part of Recommended. Block Music launches stops Music from opening and leaves the keys working (#42).
- The app now targets macOS 26 and uses the system's Liquid Glass controls.

## 1.0.3

- New opt-in tweak, Block Music launches. It stops AirPods and the play key from opening Music, closes Music if it's running, and blocks opening it by hand. Undo puts everything back. Apply it again after a macOS update replaces Music.

Contributed by vadika in #37.

## 1.0.2

- `off` no longer asks Apple's asset service to remove model sets that are already gone. It now tells an empty asset folder from a full one using what macOS reports without root, instead of treating any folder it can't list as full.

Contributed by tully-8888 in #6.

## 1.0.1

- Applying or undoing one tweak no longer resets a partly applied one, such as smart quotes off with dashes still on. A partly applied tweak only changes when you switch it yourself or name it in `undo`.
- App caches leaves alone the macOS caches whose names don't start with `com.apple.`, such as CloudKit, FamilyCircle and GeoServices.
- Removing GarageBand keeps its sound library when Logic Pro or MainStage is installed.
- Unavailable simulators and Time Machine local snapshots now say they are deleted right away instead of moved to the Trash, and the button reads Remove when either is selected.
- Background Items marks each item as an updater or a helper, and warns before a helper such as a VPN or Docker is turned off.
- When one administrator step fails, the steps after it still run.
- An undo journal that can't be read is kept aside instead of being overwritten.
- The app only reports model space it measured.
- Command-line columns no longer run together, and `off --dry-run` lists only models that are on disk.
- The README says where to find Photos Clean Up.

Contributed by Roland Kaibull in #22 to #30, and by kuishou68 in #21.

## 1.0.0

RemoveMacAI is now a debloater for macOS, with a native app. Apple Intelligence works as before and is one part of it.

- The app: an overview of the Mac, every setting with what it does, a review of each change before it happens, and Undo Everything. It opens from Applications, or with `removemacai app`. The app and the command line are the same program and share one undo history.
- 40 tweaks in six sections: Privacy (Mac Analytics, personalized ads, Improve Siri and Dictation, Improve Search, Spotlight internet results, Look Up and Safari suggestions, Game Center), Annoyances, Apple Apps, Finder, Dock and Windows, and Typing.
- Two presets: Recommended and Maximum privacy.
- Background items: other apps' launch agents and daemons, each switched off and back on.
- Storage: old macOS installers, aerial wallpaper videos, iPhone and iPad update files, Xcode leftovers, unavailable simulators, app caches, Time Machine local snapshots and Apple's optional apps, moved to the Trash.
- Locked settings share the Apple Intelligence profile, which records what it holds. Other settings are written with their previous value saved, and undo restores exactly that value.
- New commands: `tweaks`, `apply`, `undo`, `background`, `clean`, `export` and `app`. `on` turns Apple Intelligence back on and keeps the other changes; `revert` undoes everything.
- `export` writes the profile for an MDM.
- `install.sh app` installs the app in Applications.

## 0.2.5

- `off` no longer counts a model set the asset service can't size as 0. Those sizes show as unknown, and when removal fails or can't be confirmed, `off` says the run is incomplete, leaves the profile in place and exits with status 1. Contributed by Daniel Traynor in #1.
- `off --keep` says when a kept feature is switched off. `--keep` stops the profile from locking a feature, but it doesn't turn the feature back on. Reported by J-Liu in #8.

## 0.2.4

- `off` no longer gives up on every model when one set doesn't match what RemoveMacAI expects. On macOS 26.5 the Spatial Photos set failed the check, so nothing was removed. That set is now left alone and named, and the rest are removed. Reported by halilmertogut in #4.
- `--dry-run` names any set it would leave alone.

## 0.2.3

- Model sizes now come from the asset service's inventory. On some Macs, including macOS 27.0.1, the per-set status reported 0 for installed models, so `off` removed nothing. Diagnosed by Vlad Tulitu in #2.
- When `off` removes models, it also asks the asset service to remove sets whose asset folders still hold files.
- Releases are built from their tag by GitHub Actions and carry a build provenance attestation.

## 0.2.2

- Homebrew installs the prebuilt binary, so it no longer needs Xcode or the Command Line Tools.
- The release download includes `LICENSE` and `THIRD-PARTY-NOTICES.md`, with the MIT license of [pared](https://github.com/4evy/pared).

## 0.2.1

- RemoveMacAI no longer says the space is free straight after deleting the models. macOS deletes the files on its own schedule, and `off`, `status` and the README now say so.
- It says so when Apple's asset service doesn't answer, instead of reporting the models as gone.

## 0.2.0

- First public release.
