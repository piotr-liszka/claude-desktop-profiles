# AGENTS.md

Guidance for AI agents and contributors working in this repository.

## What this is

A small, dependency-free tool that creates one launcher per profile so several accounts of an Electron desktop app (Claude Desktop by default) can run side by side. Each launcher starts the app with its own `--user-data-dir`. See `README.md` for usage.

## Layout

| Path | Purpose |
| --- | --- |
| `claude-profiles` | Bash script for macOS and Linux. The whole tool lives in this one file. |
| `claude-profiles.ps1` | PowerShell script for Windows. Same commands, same behavior. |
| `tests/run.sh` | Tests, run in a throwaway `HOME`. `LIVE=1` also starts a fake app. |
| `README.md` | User-facing docs. Keep it short and simple. |

## Rules

- **Never modify the target app.** No patching, re-signing or writing inside the app bundle. The tool only creates launchers and reads the process list.
- **No network access, no downloads, no dependencies.** Use only tools that ship with the OS. Do not add an installer, package manager step or `curl | sh`.
- **Bash 3.2 compatible.** macOS ships bash 3.2: no associative arrays, no `mapfile`, no `${var,,}`. Do not use `set -e`; handle errors explicitly. Do not `source` or `eval` any file the tool wrote.
- **The launcher is self-contained.** `match_main_pid`, `find_pid`, `activate_pid` and `launch_profile` are copied into every generated launcher with `declare -f`. They must use only system tools and no globals, and changing them changes what users already have installed only after they re-run `add`.
- **Deletion is guarded.** `rm -rf` only runs on a launcher the tool created (it carries the profile marker) or on a profile folder that passed `safe_to_purge` and was confirmed. Keep it that way, and keep the bash and PowerShell versions equally strict.
- **Validate input.** Labels are `[A-Za-z0-9_-]`, 32 characters at most. Paths are made absolute and `..` is rejected. Quote every expansion; profile paths contain spaces on macOS (`Application Support`).
- **Never overwrite something the tool did not create.** Refuse and say why.
- **Keep parity.** A behavior change in `claude-profiles` needs the same change in `claude-profiles.ps1`, or a note in the README that the platforms differ.

## Testing

```bash
bash -n claude-profiles
tests/run.sh
LIVE=1 tests/run.sh   # macOS/Linux only; starts a fake `sleep` app
```

Add a test for every new behavior and every bug fix. Tests must never touch the real `HOME`, a real Claude profile or a real Claude app: use the fake app in `tests/run.sh`.

`claude-profiles.ps1` has not been run on Windows. Say so when you change it, and do not describe it as tested.

## Style

Match the existing code: short functions, plain `echo`/`printf` output, errors through `die`, comments only where the reason is not obvious. Keep the README and this file free of marketing language.
