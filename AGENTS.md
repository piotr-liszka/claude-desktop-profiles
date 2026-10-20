# AGENTS.md

Guidance for AI agents and contributors working in this repository.

## What this is

A small, dependency-free tool that gives each account of an Electron desktop app (Claude Desktop by default) its own profile so several accounts can run side by side. On macOS a profile is a copy of the app with its own name, icon, data folder and environment. See `README.md` for usage.

## Layout

| Path | Purpose |
| --- | --- |
| `claude-profiles` | Bash script for macOS and Linux. The whole tool lives in this one file. |
| `claude-profiles.ps1` | PowerShell script for Windows. Fewer features (see the README). |
| `tests/run.sh` | Tests, run in a throwaway `HOME` against a fake app. `LIVE=1` also starts it. |
| `README.md` | User-facing docs. Keep it short and simple. |

## How a macOS profile works

- `make_macos_copy` clones the installed app (`cp -c`), then edits only the clone: new `CFBundleIdentifier` and `CFBundleDisplayName`, a new icon (and `CFBundleIconName` removed so it wins), and `CFBundleExecutable` pointing at a generated `profile-launch` script. That script exports the profile's environment and `exec`s the real executable with `--user-data-dir`. The clone is then signed ad hoc.
- **`CFBundleName` must not change.** Electron derives the names of its helper apps from it; changing it makes the app crash with "Unable to find helper app".
- Restricted entitlements (keychain access groups, application identifier) cannot survive an ad-hoc signature, so the copy is signed without entitlements. Say so wherever features could be affected.
- The icon is drawn by a JXA script embedded in `badge_script` (AppKit and CoreImage, so it needs a desktop session). It scales the app's own icon to a full-bleed square so macOS applies its rounded mask cleanly, then either adds a badge (kept clear of the rounded corner) or rotates the hue of the whole image with `CIHueAdjust` for `--color`. A grey base icon has no hue to rotate, so `--color` falls back to the badge.
- `--shared-app` and Linux use a launcher instead. The launcher functions (`match_main_pid`, `find_pid`, `activate_pid`, `launch_profile`) are copied into each generated script with `declare -f`, so they may use only system tools and no globals.

## Rules

- **Never modify the installed app.** Only edit the clone, and only after it is a complete copy. Build in a `.partial` folder and move it into place only when signing succeeded.
- **No network access, no downloads, no dependencies.** Use only tools that ship with the OS. Do not add an installer, package manager step or `curl | sh`.
- **Bash 3.2 compatible.** macOS ships bash 3.2: no associative arrays, no `mapfile`, no `${var,,}`, and `"${array[@]}"` on an empty array fails under `set -u`. Do not use `set -e`; handle errors explicitly. Do not `source` or `eval` any file the tool wrote.
- **Deletion is guarded.** `rm -rf` only runs on a profile the tool created (it carries `profile.conf`) or on a folder that passed `safe_to_purge` and was confirmed. `safe_to_purge` must keep refusing `$HOME`, `~/.claude`, the app's own default folder, symlinks and relative paths. Keep the bash and PowerShell versions equally strict.
- **Validate input.** Labels are `[A-Za-z0-9_-]`, 32 characters at most. Environment names are `[A-Za-z_][A-Za-z0-9_]*`. Paths are made absolute and `..` is rejected. Quote every expansion; paths contain spaces on macOS (`Application Support`).
- **Never overwrite something the tool did not create.** Refuse and say why.
- **Do not touch system settings.** In particular, do not change the default handler for `claude://` or other URL schemes, and do not edit Launch Services or Dock preferences.
- **Keep parity or document the gap.** A behavior change in `claude-profiles` needs the same change in `claude-profiles.ps1`, or a note in the README's platform table.

## Testing

```bash
bash -n claude-profiles
tests/run.sh
LIVE=1 tests/run.sh   # macOS/Linux; starts a fake `sleep` app and draws a badge
```

Add a test for every new behavior and every bug fix. Tests must never touch the real `HOME`, a real Claude profile or the real Claude app: use the fake app in `tests/run.sh`. If you try the tool against the real Claude app, use `--dest`, `--data-dir` and `--config-dir` pointing at a scratch folder, and clean up afterwards.

`claude-profiles.ps1` has not been run on Windows, and the Linux path has not been run on Linux. Say so when you change them, and do not describe them as tested.

## Style

Match the existing code: short functions, plain `echo`/`printf` output, errors through `die`, comments only where the reason is not obvious. Keep the README and this file free of marketing language.
