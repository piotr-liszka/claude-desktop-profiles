# claude-desktop-profiles

Run more than one Claude Desktop account on the same computer, for example a personal and a work account, each signed in at the same time. On macOS every profile is its own app, with its own Dock icon and name, its own data and its own Claude Code settings.

## Quick start

```bash
git clone https://github.com/piotr-liszka/claude-desktop-profiles.git
cd claude-desktop-profiles
./claude-profiles add Work
```

Open `~/Applications/Claude Work.app`, sign in to the account you want in that profile, and pin it to your Dock if you like. Your existing Claude stays as it is, with its current account.

No dependencies and nothing to install: it is one script that uses only tools macOS already has. Read it before you run it.

## What each profile gets (macOS)

| | |
| --- | --- |
| **App** | `~/Applications/Claude <label>.app`, a copy of Claude with its own name and icon, so it has its own Dock tile. The copy is an APFS clone and uses almost no extra disk space. |
| **Icon** | The Claude icon with a coloured badge showing the label's first letter. Use `--icon` for your own, or `--no-badge` to keep Claude's. |
| **App data** | A separate folder, `~/Library/Application Support/Claude-<label>`: login, history, settings. |
| **Claude Code settings** | A separate `~/.claude-<label>` instead of `~/.claude`, so history, settings and login stay apart. |

The installed Claude is never modified.

## Commands

| Command | What it does |
| --- | --- |
| `add <label>` | Create a profile |
| `list` | Show profiles and whether each is running |
| `launch <label>` | Start a profile, or bring it to the front |
| `update [label]` | Rebuild app copies from the installed Claude (run this after Claude updates) |
| `env <label>` | Print `export` lines so a terminal can use the profile's settings |
| `remove <label>` | Delete the profile's app and keep its data |
| `remove <label> --purge` | Also delete its data and Claude Code folders (asks you to type the label) |
| `doctor` | Show what was detected on this machine |

Options for `add`:

| Option | Meaning |
| --- | --- |
| `--app PATH` | App to use (default: auto-detected Claude Desktop) |
| `--icon PATH` | Icon: `.icns`, or an image such as `.png` (square, 1024 px is best) |
| `--no-badge` | Keep the app's own icon |
| `--data-dir PATH` | App data folder |
| `--config-dir PATH` | Claude Code folder (default `~/.claude-<label>`) |
| `--no-config-dir` | Do not give the profile its own Claude Code folder |
| `--env NAME=VALUE` | Extra environment variable for the app (repeatable) |
| `--shared-app` | Do not copy the app; start the installed one through a launcher (all profiles then share one Dock tile) |
| `--dest DIR` | Where the profile is created |
| `--dry-run` | Show what would happen and change nothing |

Labels may contain letters, digits, `-` and `_`.

## Claude Code in a terminal

The profile's app uses `~/.claude-<label>`. To use the same settings and login from a terminal:

```bash
eval "$(./claude-profiles env Work)"
claude
```

## Platforms

| Platform | Script | Status |
| --- | --- | --- |
| macOS | `claude-profiles` | Tested. App copy per profile, own icon, name, data and Claude Code folder. |
| Linux | `claude-profiles` | Untested. A `.desktop` launcher with its own data folder. Pass the executable with `--app` if it is not found as `claude-desktop`. |
| Windows | `claude-profiles.ps1` | Experimental, untested. A Start Menu shortcut with its own data folder and icon. No app copy and no separate Claude Code folder yet. |

## Other apps

The script is not tied to Claude. It works with any app that honors the Chromium `--user-data-dir` flag, which Electron apps do:

```bash
./claude-profiles add Work --app "/Applications/Some App.app" --env SOME_VAR=value
```

## Good to know

- **Updates.** Copies do not auto-update, because they are no longer signed by Anthropic. After Claude updates, run `./claude-profiles update` to rebuild them. Quit the profile first.
- **Signing.** Editing the copy breaks its signature, so it is signed ad hoc on your machine. macOS may ask once for Keychain access, and permissions such as camera or screen recording are granted per copy. Features that rely on Anthropic's signature (passkeys, security keys, Microsoft single sign-on) may not work in a copy. If you need them, create that profile with `--shared-app`.
- **Sign-in.** Sign-in returns to the app through a link that macOS delivers to one app. If it opens the wrong window, quit the other profile while you sign in, then start it again.
- **Disk space.** Each profile keeps its own data, including anything large the app downloads for itself.
- **Safety.** The tool only creates files in the folder you give it (`~/Applications` by default) and reads the process list. `--purge` refuses anything that does not look like a dedicated profile folder, never touches `~/.claude` or the app's own default folder, and asks you to type the label first.

## Remove everything

```bash
./claude-profiles remove Work --purge
```

## Tests

```bash
tests/run.sh           # unit and CLI tests in a throwaway HOME, using a fake app
LIVE=1 tests/run.sh    # also starts the fake app through the generated profiles and draws a badge
```

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. Claude is a trademark of Anthropic.

## License

MIT
