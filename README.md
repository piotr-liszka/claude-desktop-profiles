# claude-desktop-profiles

Run more than one Claude Desktop account on the same computer, for example a personal and a work account, each in its own window and signed in at the same time.

Each profile gets its own launcher and its own data folder (login, history, settings). The installed app is never modified.

## Quick start

```bash
git clone https://github.com/piotr-liszka/claude-desktop-profiles.git
cd claude-desktop-profiles
./claude-profiles add Work
```

Then open the new launcher (`~/Applications/Claude Work.app` on macOS), sign in to the account you want in that profile, and pin it to your Dock if you like. Your existing Claude stays as it is and keeps its current account.

No dependencies and nothing to install: it is one script that uses only tools your system already has. Read it before you run it; it is short.

## Commands

| Command | What it does |
| --- | --- |
| `add <label>` | Create a launcher with its own profile |
| `list` | Show launchers and whether each profile is running |
| `launch <label>` | Start a profile, or bring it to the front if it is already running |
| `remove <label>` | Delete the launcher and keep the profile data |
| `remove <label> --purge` | Also delete the profile folder (asks you to type the label) |
| `doctor` | Show what was detected on this machine |

Options for `add`:

| Option | Meaning |
| --- | --- |
| `--app PATH` | App to launch (default: auto-detected Claude Desktop) |
| `--data-dir PATH` | Profile folder (default: the app's data folder with `-<label>` added) |
| `--dest DIR` | Where to write the launcher |
| `--icon PATH` | Launcher icon (default: the app's own icon on macOS) |
| `--dry-run` | Show what would happen and change nothing |

Labels may contain letters, digits, `-` and `_`.

## Platforms

| Platform | Script | Status |
| --- | --- | --- |
| macOS | `claude-profiles` | Tested |
| Linux | `claude-profiles` | Untested. Creates a `.desktop` entry. Pass the executable with `--app` if it is not found as `claude-desktop`. |
| Windows | `claude-profiles.ps1` | Experimental, untested. Creates Start Menu shortcuts. Pass `-AppPath` if the app is not found. |

## Other apps

The script is not tied to Claude. It works with any app that honors the Chromium `--user-data-dir` flag (Electron apps do):

```bash
./claude-profiles add Work --app "/Applications/Some App.app"
```

## Good to know

- **Sign-in.** Sign-in may hand control back to the app through a link that macOS delivers to only one window. If it lands in the wrong one, quit the other instance while you sign in, then start it again.
- **One launcher per profile.** Starting the same profile twice can corrupt its data. The launchers check for a running instance and focus it instead; use them (or `launch`) rather than starting the app by hand with the same folder.
- **Dock.** Running instances show the app's own icon, so two profiles look alike in the Dock. Use the launcher names to tell them apart.
- **Updates.** The launchers point at the installed app, so app updates need no action here. If the app moves, run `add` again.
- **Safety.** The tool only creates launcher files and reads the process list. `--purge` refuses anything that does not look like a dedicated profile folder and asks you to type the label first.

## Remove everything

```bash
./claude-profiles remove Work --purge
```

Or delete the launcher and the profile folder by hand.

## Tests

```bash
tests/run.sh          # unit and CLI tests in a throwaway HOME
LIVE=1 tests/run.sh   # also starts a fake app through a generated launcher
```

## Disclaimer

Unofficial. Not affiliated with or endorsed by Anthropic. Claude is a trademark of Anthropic.

## License

MIT
