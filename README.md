<p align="center">
  <img src="docs/hero.png" alt="RemoveMacAI" width="840">
</p>

# RemoveMacAI

Turn off Apple Intelligence on macOS 27 and remove its downloaded models.

macOS 27 no longer has a single switch for Apple Intelligence, and its models stay on disk after the features are turned off. RemoveMacAI turns the features off, removes the models (about 12 GB) and prevents macOS from downloading them again. All changes can be reverted.

<p align="center">
  <img src="docs/terminal.gif" alt="RemoveMacAI turning off Apple Intelligence" width="840">
</p>

<p align="center"><a href="docs/demo.mp4">Demo video</a></p>

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash
```

The script downloads the latest release, verifies its SHA-256 checksum and runs it from a temporary directory. Nothing is installed.

With Homebrew:

```sh
brew install omlahore/tap/removemacai
removemacai
```

RemoveMacAI shows the current state and asks for confirmation. It then opens System Settings to install its configuration profile, which macOS requires the user to approve, and removes the models.

## Usage

| Command | Description |
|---|---|
| `removemacai` | Show the current state, then turn Apple Intelligence off |
| `removemacai status` | Show each feature and the size of the models on disk |
| `removemacai scan` | Show, for each model set, what is on disk, who uses it and what `off` would do, without changing anything |
| `removemacai off --keep <features>` | Leave the listed features on |
| `removemacai off --dry-run` | Show the changes without applying them |
| `removemacai revert` | Undo all changes |
| `removemacai features` | List the feature names accepted by `--keep` |

To revert with the one-line installer:

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash -s revert
```

## What it changes

**Features turned off:** Siri (including "Hey Siri" and the menu bar icon), dictation, the Apple Intelligence Report, Writing Tools, Genmoji, Image Playground, the ChatGPT extension, summaries in Mail, Messages, Safari, Notes and notifications, Notes transcription, Mail smart replies, inline text predictions, Spatial Photos, Photos Clean Up, Xcode predictive code completion, Shortcuts AI generation and handwriting synthesis.

**Models removed:** the Apple Intelligence foundation models and the models for image generation and Genmoji, Spatial Photos, Photos Clean Up and Xcode code completion; Siri voices, understanding, listening, dialog and planner models; speech recognition; the Shortcuts generator, handwriting synthesis and Safari browsing assistant models; and the summaries and foundation model safety configuration. Spelling, dictionary, Spotlight and Translation data are left alone.

<p align="center">
  <img src="docs/status.png" alt="Output of removemacai status" width="620">
</p>

## How it works

- A configuration profile applies Apple's restriction keys for Apple Intelligence and forces the settings that have no restriction key.
- Models are removed through Apple's asset service. System Integrity Protection stays enabled and no files under `/System` are modified directly.
- The profile redirects the download of each removed model to a closed local port, so macOS does not download it again.
- Removing the profile restores the previous settings. macOS downloads the models again when a feature needs them.

RemoveMacAI makes no network requests and collects no data.

## FAQ

**Does dictation still work?**
No, it is turned off along with its speech recognition models. Run `removemacai off --keep dictation` to leave it on.

**Do macOS updates undo the changes?**
No. The profile, including the download block, persists across updates.

**Storage settings still lists Apple Intelligence after the models were deleted.**
Apple's asset service releases the models right away, but macOS deletes the files on its own schedule. Until then, System Settings > General > Storage keeps counting them under Apple Intelligence.

**Why is a process named Siri still running?**
In macOS 27 the Spotlight window runs as a process named Siri. Some system services also stay loaded; they are protected by System Integrity Protection.

**What stops working?**
The features listed above, apps that use Apple's on-device models (the Foundation Models framework and the Use Model action in Shortcuts), Visual Intelligence and natural-language editing in Calendar.

## Requirements

macOS 27 on Apple silicon.

## Uninstall

Run `removemacai revert`, then `brew uninstall removemacai` if it was installed with Homebrew.

## Acknowledgements

The asset service interface and several of the settings keys were first documented by [pared](https://github.com/4evy/pared).

## License

[MIT](LICENSE)
