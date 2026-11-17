# Usage

## Commands

| Command | What it does |
| --- | --- |
| `add <label>` | Create a profile |
| `list` | Show profiles and whether each is running. `--json` prints them for other programs. |
| `launch <label>` | Start a profile, or bring it to the front |
| `quit <label>` | Quit a running profile |
| `icon <label> --color COLOR` | macOS: change a profile's icon and keep its data and settings. Instead of `--color`: `--icon PATH`, `--badge` or `--no-badge`. `--restart` quits and reopens it if it is open. |
| `update [label]` | Rebuild app copies from the installed Claude, all of them without a label. `--outdated` skips copies already at the installed version; `--restart` quits open profiles and reopens them. |
| `install-updater` | macOS: create `~/Applications/Claude Profiles Updater.app` (see below) |
| `env <label>` | Print `export` lines so a terminal uses the profile's Claude Code settings |
| `remove <label>` | Delete the profile's app, keep its data |
| `remove <label> --purge` | Also delete its data and Claude Code folders (asks you to type the label) |
| `doctor` | Show what was detected on this machine |

Labels may contain letters, digits, `-` and `_`.

## Options for `add`

| Option | Meaning |
| --- | --- |
| `--app PATH` | App to use (default: auto-detected Claude Desktop) |
| `--color COLOR` | Turn the whole icon to this colour instead of adding a badge: `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink` or a hex such as `#3b82f6`. Grey, black and white are refused. |
| `--icon PATH` | Your own icon: `.icns` or an image such as `.png` (square, 1024 px is best). Wins over `--color`. |
| `--no-badge` | Keep the app's own icon |
| `--data-dir PATH` | App data folder |
| `--config-dir PATH` | Claude Code folder (default `~/.claude-<label in lowercase>`) |
| `--no-config-dir` | Do not give the profile its own Claude Code folder |
| `--env NAME=VALUE` | Extra environment variable for the app (repeatable) |
| `--shared-app` | Do not copy the app; start the installed one through a launcher. All such profiles share one Dock tile. |
| `--dest DIR` | Where the profile is created |
| `--dry-run` | Show what would happen and change nothing |

## Changing the icon

```bash
./claude-profiles icon Work --color blue --restart
```

The icon is `Contents/Resources/profile.icns` inside the profile's app. `update` keeps it.

## Updating after Claude updates

Copies do not update themselves, because they are no longer signed by Anthropic. If a profile offers to install an update, close the message. Let the original Claude update, then:

- use the menu bar app's **Update** buttons, or
- open **Claude Profiles Updater** (create it once with `./claude-profiles install-updater`; run that again after you change the script; log in `~/Library/Logs/claude-profiles-updater.log`), or
- run `./claude-profiles update --outdated --restart`. It refuses to run from a terminal inside a profile it would quit.

## Menu bar app

`menubar/build.sh` builds `~/Applications/Claude Profiles Menu.app` with Apple's Swift compiler (Xcode or `xcode-select --install`), macOS 13 or later. Options: `--dest DIR`, `--open`, `--universal`. The app carries its own copy of `claude-profiles` and runs it for every action, so build it again after you change the script.

Release builds are signed ad hoc, not notarized. To open one the first time, right-click it and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine "$HOME/Applications/Claude Profiles Menu.app"
```

**Open at Login** is in its settings menu. If your profiles are not in `~/Applications`:

```bash
defaults write local.claude-profiles.menubar ProfilesDest /path/to/folder
```

## Claude Code in a terminal

```bash
eval "$(./claude-profiles env Work)"
claude
```

## Platforms

| Platform | Script | Status |
| --- | --- | --- |
| macOS | `claude-profiles` | Tested. App copy per profile, own icon, name, data and Claude Code folder. |
| Linux | `claude-profiles` | Untested. A `.desktop` launcher with its own data folder. Pass the executable with `--app` if it is not found as `claude-desktop`. |
| Windows | `claude-profiles.ps1` | Experimental, untested. A Start Menu shortcut with its own data folder and icon. No app copy, separate Claude Code folder, `list --json`, `quit` or menu bar app. |

## Other apps

Any app that honors the Chromium `--user-data-dir` flag works, which Electron apps do:

```bash
./claude-profiles add Work --app "/Applications/Some App.app" --env SOME_VAR=value
```

## Good to know

- **Signing.** The copy is signed ad hoc on your machine. macOS may ask once for Keychain access, and permissions such as camera or screen recording are granted per copy. Features that rely on Anthropic's signature (passkeys, security keys, Microsoft single sign-on) may not work; use `--shared-app` for those profiles.
- **Sign-in.** Sign-in returns to the app through a link that macOS delivers to one app. If it opens the wrong window, quit the other profile while you sign in.
- **Disk space.** Each profile keeps its own data.
- **Safety.** The tool only creates files in the folder you give it (`~/Applications` by default) and reads the process list. `--purge` refuses anything that does not look like a dedicated profile folder, never touches `~/.claude` or the app's default folder, and asks you to type the label first.

## Tests

```bash
tests/run.sh           # in a throwaway HOME, using a fake app
LIVE=1 tests/run.sh    # also starts the fake app and draws a badge
```
