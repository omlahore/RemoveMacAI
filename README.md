<p align="center">
  <img src="docs/hero.png" alt="RemoveMacAI" width="840">
</p>

# RemoveMacAI

Turn off Apple Intelligence on macOS 27 and remove its downloaded models.

Built on [pared](https://github.com/4evy/pared) by 4evy, who did the hard work first: mapping Apple's asset service, the model sets and the settings keys this tool relies on.

macOS 27 no longer has a single switch for Apple Intelligence, and its models stay on disk after the features are turned off. RemoveMacAI turns the features off, removes the models and prevents macOS from downloading them again. All changes can be reverted.

[MacRumors](https://www.macrumors.com/2026/10/05/apple-intelligence-removal-tool-frees-mac-storage/), [AppleInsider](https://appleinsider.com/articles/26/10/05/dumb-down-your-mac-save-12gb-by-removing-apple-intelligence) and [Help Net Security](https://www.helpnetsecurity.com/2026/10/05/removemacai-turn-off-apple-intelligence/) have written about RemoveMacAI.

<p align="center">
  <img src="docs/terminal.gif" alt="RemoveMacAI turning off Apple Intelligence" width="840">
</p>

<p align="center"><a href="docs/demo.mp4">Demo video</a></p>

## Install

Open Terminal (Applications > Utilities), paste this line and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash
```

The script downloads the latest release, verifies its SHA-256 checksum and runs it from a temporary directory. Nothing is installed.

With Homebrew:

```sh
brew install omlahore/tap/removemacai
removemacai
```

With [packslip](https://packslip.dev/docs/bootstrap/) (1.5.1 or newer):

```sh
packslip install github.com/omlahore/RemoveMacAI &&
  ~/.local/bin/removemacai
```

Or with [mise](https://mise.jdx.dev/dev-tools/backends/packslip.html):

```sh
mise use -g packslip:github.com/omlahore/RemoveMacAI &&
  mise exec -- removemacai
```

Both require a release with `packslip.sigstore.json`; v0.2.5 and earlier have none.

To skip the script, download `removemacai-darwin-arm64.tar.gz` and its `.sha256` file from the [latest release](https://github.com/omlahore/RemoveMacAI/releases/latest), then run this in the folder you saved them to:

```sh
shasum -a 256 -c removemacai-darwin-arm64.tar.gz.sha256 &&
tar xzf removemacai-darwin-arm64.tar.gz &&
xattr -dr com.apple.quarantine removemacai &&
./removemacai
```

The binary is ad-hoc signed but not notarized, so macOS won't run a copy downloaded through a browser until the quarantine flag is removed.

RemoveMacAI shows the current state and asks for confirmation. It then opens System Settings to install its configuration profile, which macOS requires the user to approve, and removes the models.

To leave some features on, name them with `--keep`. For example, to turn everything off except the Photos features:

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash -s -- off --keep spatial-photos,photos-clean-up
```

`removemacai features` lists the names.

### Verify a download

Check build provenance with the [GitHub CLI](https://cli.github.com/):

```sh
gh attestation verify removemacai-darwin-arm64.tar.gz -R omlahore/RemoveMacAI
```

To verify a signed manifest, download `packslip.sigstore.json` and the archive from the same release:

```sh
packslip verify packslip.sigstore.json \
  --identity-prefix https://github.com/omlahore/RemoveMacAI/ \
  --issuer https://token.actions.githubusercontent.com \
  --artifact removemacai-darwin-arm64.tar.gz
```

## Usage

| Command | Description |
|---|---|
| `removemacai` | Show the current state, then turn Apple Intelligence off |
| `removemacai status` | Show each feature and the size of the models on disk |
| `removemacai off --keep <features>` | Leave the listed features alone (one that is already off stays off until you turn it on) |
| `removemacai off --dry-run` | Show the changes without applying them |
| `removemacai revert` | Undo all changes |
| `removemacai features` | List the feature names accepted by `--keep` |

Model sizes that the asset service cannot report are shown as `unknown`. If model removal fails or cannot be confirmed, `off` exits with status 1 and leaves the configuration profile active. Check the reported warnings and run `removemacai status` before trying again.

To revert with the one-line installer:

```sh
curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash -s revert
```

## What it changes

**Features turned off:** Siri (including "Hey Siri" and the menu bar icon), Writing Tools, Genmoji, Image Playground, the ChatGPT extension, summaries in Mail, Messages, Safari, Notes and notifications, Mail smart replies, inline text predictions, Spatial Photos, Photos Clean Up and Xcode predictive code completion.

**Models removed:** the Apple Intelligence foundation models and the models for image generation and Genmoji, Spatial Photos, Photos Clean Up and Xcode code completion.

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
Yes. Dictation is a separate setting, and its speech models are not removed.

**Do macOS updates undo the changes?**
No. The profile, including the download block, persists across updates.

**Storage settings still lists Apple Intelligence after the models were deleted.**
Apple's asset service releases the models right away, but macOS deletes the files on its own schedule. Until then, System Settings > General > Storage keeps counting them under Apple Intelligence.

**Why is a process named Siri still running?**
In macOS 27 the Spotlight window runs as a process named Siri. Some system services also stay loaded; they are protected by System Integrity Protection.

**What stops working?**
The features listed above, apps that use Apple's on-device models (the Foundation Models framework and the Use Model action in Shortcuts), Visual Intelligence and natural-language editing in Calendar.

## Requirements

Apple silicon.

| macOS | Status |
|---|---|
| 27 | Supported, tested on 27.0. On 27.0.1, use 0.2.3 or later. |
| 26 and earlier | Not supported |

## Uninstall

Run `removemacai revert`, then `brew uninstall removemacai` if it was installed with Homebrew.

## Acknowledgements

RemoveMacAI is built on [pared](https://github.com/4evy/pared), a complete working tool by 4evy that first mapped the asset service, the model sets and several of the settings keys. Its license is in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Support

If RemoveMacAI is useful to you, you can [sponsor it on GitHub](https://github.com/sponsors/omlahore).

## Author

I'm [Om Lahore](https://github.com/omlahore) and I'm open to new roles. You can reach me on [LinkedIn](https://linkedin.com/in/om-lahorey) or at omlahorey@gmail.com.

## License

[MIT](LICENSE)
