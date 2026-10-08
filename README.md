<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screens/overview-dark.webp">
    <img src="docs/screens/overview-light.webp" alt="The RemoveMacAI app" width="840">
  </picture>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/275773?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-275773" target="_blank" rel="noopener noreferrer"><img src="https://raw.githubusercontent.com/omlahore/omlahore/main/profile/trendshift-daily.svg" alt="omlahore%2FRemoveMacAI | Trendshift" width="250" height="55"/></a> <a href="https://trendshift.io/repositories/275773?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-275773" target="_blank" rel="noopener noreferrer"><img src="https://raw.githubusercontent.com/omlahore/omlahore/main/profile/trendshift-weekly.svg" alt="omlahore%2FRemoveMacAI | Trendshift" width="250" height="55"/></a>
</p>

# RemoveMacAI

Debloat macOS. Turn off Apple Intelligence and delete its models, stop the analytics and ads, quiet the pop-ups, switch off other apps' background updaters and get disk space back. You see every change before it happens, and every change can be undone.

<p align="center">
  <a href="https://github.com/omlahore/RemoveMacAI/releases/latest/download/RemoveMacAI.zip"><img src="docs/download.svg" alt="Download for Mac" width="236" height="56"></a>
</p>

<p align="center">
  <a href="https://omlahore.github.io/RemoveMacAI/">omlahore.github.io/RemoveMacAI</a>
</p>

Built on [pared](https://github.com/4evy/pared) by 4evy, who did the hard work first: mapping Apple's asset service, the model sets and the settings keys the Apple Intelligence part relies on.

[The Verge](https://www.theverge.com/ai-artificial-intelligence/1004672/mac-delete-apple-intelligence-ai-tool), [Ars Technica](https://arstechnica.com/apple/2026/10/command-line-tool-quickly-removes-apple-intelligence-from-macos-27/), [The Register](https://www.theregister.com/ai-and-ml/2026/10/05/get-rid-of-apples-ai-bloatware-and-reclaim-12-gb-of-storage-with-this-open-source-tool/5301213), [MacRumors](https://www.macrumors.com/2026/10/05/apple-intelligence-removal-tool-frees-mac-storage/), [AppleInsider](https://appleinsider.com/articles/26/10/05/dumb-down-your-mac-save-12gb-by-removing-apple-intelligence) and [Help Net Security](https://www.helpnetsecurity.com/2026/10/05/removemacai-turn-off-apple-intelligence/) have written about RemoveMacAI, and [Daring Fireball](https://daringfireball.net/linked/2026/10/06/cli-tool-removes-apple-intelligence-from-macos-27) linked to it.

## Install

### The app

Open Terminal (Applications > Utilities), paste this line and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash -s app
```

It downloads the latest release, checks its SHA-256 checksum, puts RemoveMacAI in Applications and opens it.

To download it yourself instead, get `RemoveMacAI.zip` from the [latest release](https://github.com/omlahore/RemoveMacAI/releases/latest), unzip it and drag RemoveMacAI to Applications. The app is not notarized, so the first time you open it macOS says it can't verify it. Open System Settings > Privacy & Security, scroll down and click Open Anyway.

### The command line

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash
```

This runs the command-line version from a temporary folder and installs nothing. With Homebrew:

```sh
brew install omlahore/tap/removemacai
```

The app and the command line are the same program and share the same undo history.

## What it does

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screens/privacy-dark.webp">
    <img src="docs/screens/privacy-light.webp" alt="Privacy settings in RemoveMacAI" width="840">
  </picture>
</p>

| Section | What you can turn off or change |
|---|---|
| Apple Intelligence | Siri, Writing Tools, Genmoji, Image Playground, ChatGPT, summaries in Mail, Messages, Safari, Notes and notifications, inline predictions, Spatial Photos, Photos Clean Up, Xcode predictive completion. The models are deleted and blocked from downloading again. Keep any feature you use. |
| Privacy | Mac Analytics, personalized ads, Improve Siri and Dictation, Improve Search, Spotlight internet results, Look Up suggestions, Safari search suggestions, Game Center |
| Annoyances | Clicking the wallpaper hiding every window, desktop widgets, the play key opening Music, all Music launches (including AirPods; opt-in), iPhone Mirroring |
| Apple apps | Apple Music in the Music app, the Book Store, unused Apple apps in the Dock |
| Finder | File extensions, hidden files, the path and status bars, folders first, searching the current folder, the extension warning, `.DS_Store` files on network drives, emptying the Trash after 30 days, saving to your Mac instead of iCloud, the Library folder |
| Dock and windows | Recent apps, the auto-hide delay, bouncing icons, minimizing into the app icon, window animations, gaps between tiled windows, screenshot shadows |
| Typing | Autocorrect, smart quotes and dashes, the double-space period, automatic capitals, the accent menu on held keys |
| Background items | Updaters and helpers other apps install, such as Google's updater, shown with what they run and switched off one by one |
| Storage | Old macOS installers, aerial wallpaper videos, iPhone and iPad update files, Xcode build data and device support, unavailable simulators, app caches, Time Machine local snapshots, and Apple's optional apps (GarageBand and its sound library, iMovie, Keynote, Numbers, Pages) |

Two presets get you started. **Recommended** turns Apple Intelligence, analytics and ads off and removes the pop-ups, and leaves alone anything you rely on. **Maximum privacy** adds Game Center and Safari's search suggestions. Both add to what is already applied, and nothing changes until you review it.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screens/review-dark.webp">
    <img src="docs/screens/review-light.webp" alt="Reviewing changes before they are applied" width="600">
  </picture>
</p>

## Command line

| Command | Description |
|---|---|
| `removemacai` | Show the state of Apple Intelligence, then turn it off |
| `removemacai status` | Show each Apple Intelligence feature and the size of its models |
| `removemacai off --keep <features>` | Turn Apple Intelligence off but leave the listed features on |
| `removemacai on` | Turn Apple Intelligence back on and keep the other changes |
| `removemacai tweaks` | List every tweak and whether it is applied (`--json` for scripts) |
| `removemacai apply <tweaks>` | Apply tweaks by name |
| `removemacai apply --preset recommended` | Apply a preset, Apple Intelligence off included |
| `removemacai undo <tweaks>` | Undo tweaks by name |
| `removemacai background` | List other apps' background items; `off` or `on` with their labels |
| `removemacai clean` | Show the space you can get back; name items to move them to the Trash |
| `removemacai export <file>` | Write the configuration profile for an MDM |
| `removemacai revert` | Undo everything RemoveMacAI changed |
| `removemacai app` | Open the app |

`apply`, `undo`, `background` and `clean` show the change first and ask. `--dry-run` shows it and stops, and `--yes` skips the question.

<p align="center">
  <img src="docs/terminal.gif" alt="RemoveMacAI turning off Apple Intelligence in Terminal" width="840">
</p>

<p align="center"><a href="docs/demo.mp4">Demo video</a></p>

## For Mac admins

`removemacai export` writes the same configuration profile the app installs, so you can deploy it with Jamf, Kandji, Intune or any other MDM:

```sh
removemacai export RemoveMacAI.mobileconfig --preset recommended
removemacai export AI-off.mobileconfig --keep writing-tools
removemacai export Privacy.mobileconfig --no-ai analytics personalized-ads spotlight-web
```

It holds the Apple Intelligence restrictions, the download block for removed models and the locked tweaks. Per-user tweaks such as Finder and Dock settings aren't in the profile; `removemacai apply` sets those on each Mac. `removemacai tweaks --json` reports the state of every tweak for compliance scripts.

## How it works

- **Locked settings** (Apple Intelligence and the tweaks marked with a lock) go in one configuration profile that you approve in System Settings, because macOS requires that. Removing the profile undoes all of them.
- **Other settings** are written the way `defaults write` writes them. RemoveMacAI first records each setting's previous value in `~/Library/Application Support/RemoveMacAI/journal.json`, and undo puts back exactly that value.
- **Models** are removed through Apple's asset service, and the profile points their downloads at a closed local port so macOS doesn't fetch them again.
- **Storage** cleanup moves files to the Trash, so they aren't gone until you empty it. Unavailable simulators and Time Machine local snapshots are deleted right away by `simctl` and `tmutil`.

System Integrity Protection stays on, nothing under `/System` is modified, and RemoveMacAI makes no network requests and collects no data.

## What it doesn't do

- **Delete Apple's built-in apps.** They live on the sealed system volume. Removing them needs System Integrity Protection off, and a failed attempt can leave the Mac unable to start. RemoveMacAI quiets them instead and removes the optional apps that Apple lets you delete.
- **Mass-disable Apple's background services.** With System Integrity Protection on, macOS refuses to unload most of them, and many start again whenever an app asks for them. RemoveMacAI switches off the one that unloads cleanly (the play key opening Music) and other apps' background items.

## FAQ

**Does dictation still work?**
Yes. Dictation is a separate setting, and its speech models are not removed.

**Where do I use Photos Clean Up after keeping it enabled?**
Open a photo in Photos, choose **Edit**, then **Tools > Clean Up**. Photos Clean Up is not a separate switch in System Settings.

**Do macOS updates undo the changes?**
The profile persists across updates. If an update resets one of the other settings, RemoveMacAI shows it as not applied and you can apply it again.

**Storage settings still lists Apple Intelligence after the models were deleted.**
Apple's asset service releases the models right away, but macOS deletes the files on its own schedule. Until then, System Settings > General > Storage keeps counting them under Apple Intelligence.

**Why is a process named Siri still running?**
In macOS 27 the Spotlight window runs as a process named Siri. Some system services also stay loaded; they are protected by System Integrity Protection.

**What stops working when Apple Intelligence is off?**
The features listed above, apps that use Apple's on-device models (the Foundation Models framework and the Use Model action in Shortcuts), Visual Intelligence and natural-language editing in Calendar.

## Requirements

Apple silicon.

| macOS | Status |
|---|---|
| 27 | Supported, tested on 27.0. On 27.0.1, use 0.2.3 or later. |
| 26 and earlier | Not supported |

## Uninstall

Run `removemacai revert` or click Undo Everything in the app, then delete the app or run `brew uninstall removemacai`.

## Acknowledgements

The Apple Intelligence part of RemoveMacAI is built on [pared](https://github.com/4evy/pared), a complete working tool by 4evy that first mapped the asset service, the model sets and several of the settings keys. Its license is in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Support

If RemoveMacAI is useful to you, you can [sponsor it on GitHub](https://github.com/sponsors/omlahore).

## Author

I'm [Om Lahore](https://github.com/omlahore) and I'm open to new roles. You can reach me on [LinkedIn](https://linkedin.com/in/om-lahorey) or at omlahorey@gmail.com.

## License

[MIT](LICENSE)
