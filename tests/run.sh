#!/bin/bash
# Tests for claude-profiles (macOS and Linux).
# Everything runs in a throwaway HOME; your real profiles are never touched.
# Set LIVE=1 to also start a fake app through a generated launcher.

cd "$(dirname "$0")/.." || exit 1
TOOL_PATH="$PWD/claude-profiles"

passes=0
fails=0
ok()  { passes=$((passes + 1)); echo "ok   $1"; }
bad() { fails=$((fails + 1)); echo "FAIL $1"; }
expect_ok()   { local d="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
expect_fail() { local d="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }
equals()      { [ "$1" = "$2" ]; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/claude-profiles-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME XDG_DATA_HOME

# Sourcing defines the functions without running main.
. "$TOOL_PATH"
detect_os
tool() { "$TOOL_PATH" "$@"; }

# A fake app that only sleeps, so nothing real is ever started.
if [ "$OS" = macos ]; then
  FAKE="$WORK/Fake.app"
  mkdir -p "$FAKE/Contents/MacOS"
  printf '#!/bin/bash\nsleep 60\n' > "$FAKE/Contents/MacOS/fake"
  chmod +x "$FAKE/Contents/MacOS/fake"
  cat > "$FAKE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>fake</string>
  <key>CFBundleIdentifier</key><string>test.fake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
  DEST="$HOME/Applications"
  DEFAULT_DATA="$HOME/Library/Application Support/Fake"
  WORK_DATA="$HOME/Library/Application Support/Fake-Work"
  LAUNCHER="$DEST/Fake Work.app"
  SCRIPT="$LAUNCHER/Contents/MacOS/launch"
else
  FAKE="$WORK/fake"
  printf '#!/bin/bash\nsleep 60\n' > "$FAKE"
  chmod +x "$FAKE"
  DEST="$HOME/.local/share/applications"
  DEFAULT_DATA="$HOME/.config/fake"
  WORK_DATA="$HOME/.config/fake-Work"
  LAUNCHER="$DEST/fake-work.desktop"
  SCRIPT="$HOME/.local/share/claude-profiles/fake-work.sh"
fi

echo "== helpers"
PS_FIXTURE=$(cat <<'EOF'
  100 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/h/Application Support/Claude-Work
  101 /x/Claude Helper (Renderer) --type=renderer --user-data-dir=/h/Application Support/Claude-Work
  200 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/h/Application Support/Claude-Work2
  300 /Applications/Claude.app/Contents/MacOS/Claude
EOF
)
equals "$(echo "$PS_FIXTURE" | match_main_pid "/h/Application Support/Claude-Work")" 100 && ok "finds the main process, not helpers" || bad "finds the main process, not helpers"
equals "$(echo "$PS_FIXTURE" | match_main_pid "/h/Application Support/Claude-Work2")" 200 && ok "does not confuse Work with Work2" || bad "does not confuse Work with Work2"
equals "$(echo "$PS_FIXTURE" | match_main_pid "/h/Application Support/Claude-Wor")" "" && ok "a prefix of a profile path does not match" || bad "a prefix of a profile path does not match"
equals "$(echo "$PS_FIXTURE" | match_main_pid "/h/Application Support/Claude-None")" "" && ok "unknown profile has no pid" || bad "unknown profile has no pid"

expect_ok   "label: letters and digits" check_label Work2
expect_ok   "label: dash and underscore" check_label my_Work-1
expect_fail "label: space rejected" check_label "a b"
expect_fail "label: slash rejected" check_label "a/b"
expect_fail "label: leading dash rejected" check_label "-x"
expect_fail "label: empty rejected" check_label ""
expect_fail "label: too long rejected" check_label "$(printf 'a%.0s' $(seq 1 33))"

equals "$(absolute_path /a/b/)" /a/b && ok "absolute_path strips trailing slash" || bad "absolute_path strips trailing slash"
equals "$(absolute_path /)" / && ok "absolute_path keeps the root" || bad "absolute_path keeps the root"
expect_fail "absolute_path rejects .." absolute_path /a/../b
equals "$(slugify 'Fake Work')" fake-work && ok "slugify" || bad "slugify"

echo "== add"
tool add Work --app "$FAKE" --dry-run >"$WORK/dry.out" 2>&1
grep -q "would create" "$WORK/dry.out" && [ ! -e "$DEST" ] && ok "dry run prints the plan and writes nothing" || bad "dry run prints the plan and writes nothing"

expect_ok "add creates a launcher" tool add Work --app "$FAKE"
[ -e "$LAUNCHER" ] && ok "launcher exists" || bad "launcher exists"
[ -x "$SCRIPT" ] && ok "launch script is executable" || bad "launch script is executable"
expect_ok "launch script is valid bash" bash -n "$SCRIPT"
tail -n 1 "$SCRIPT" | grep -q '^launch_profile ' && ok "launch script ends by launching the profile" || bad "launch script ends by launching the profile"
grep -q '^match_main_pid' "$SCRIPT" && ok "launch script is self-contained" || bad "launch script is self-contained"
if [ "$OS" = macos ]; then
  expect_ok "Info.plist is valid" plutil -lint "$LAUNCHER/Contents/Info.plist"
  equals "$(conf_get "$LAUNCHER/Contents/Resources/profile.conf" DATA_DIR)" "$WORK_DATA" && ok "profile folder sits next to the default one" || bad "profile folder sits next to the default one"
else
  grep -q '^Exec=' "$LAUNCHER" && equals "$(conf_get "$LAUNCHER" X-ClaudeProfiles-DATA_DIR)" "$WORK_DATA" && ok ".desktop entry has Exec and profile folder" || bad ".desktop entry has Exec and profile folder"
fi
expect_ok "adding again regenerates the launcher" tool add Work --app "$FAKE"

expect_fail "bad label is rejected" tool add "bad/label" --app "$FAKE"
expect_fail "the app's default profile is refused" tool add Main --app "$FAKE" --data-dir "$DEFAULT_DATA"
expect_fail "missing app is refused" tool add Work --app "$WORK/nope"

if [ "$OS" = macos ]; then
  mkdir -p "$DEST/Fake Foreign.app"
  expect_fail "does not overwrite a foreign app" tool add Foreign --app "$FAKE"
  [ -d "$DEST/Fake Foreign.app" ] && ok "foreign app is untouched" || bad "foreign app is untouched"
fi

echo "== list"
tool list >"$WORK/list.out" 2>&1
grep -q "^Work" "$WORK/list.out" && grep -q "stopped" "$WORK/list.out" && ok "list shows the launcher as stopped" || bad "list shows the launcher as stopped"
tool list --dest "$WORK/empty" 2>&1 | grep -q "no launchers" && ok "list on an empty folder" || bad "list on an empty folder"

echo "== remove"
mkdir -p "$WORK_DATA"; echo x > "$WORK_DATA/Local State"
expect_ok "remove deletes the launcher" tool remove Work
[ ! -e "$LAUNCHER" ] && ok "launcher is gone" || bad "launcher is gone"
[ -f "$WORK_DATA/Local State" ] && ok "profile data is kept by default" || bad "profile data is kept by default"
expect_fail "remove of an unknown label fails" tool remove Work

tool add Work --app "$FAKE" >/dev/null 2>&1
expect_fail "purge without a terminal or --yes is refused" tool remove Work --purge </dev/null
[ -f "$WORK_DATA/Local State" ] && ok "refused purge deletes nothing" || bad "refused purge deletes nothing"
expect_ok "purge with --yes" tool remove Work --purge --yes
[ ! -e "$WORK_DATA" ] && ok "profile data is deleted by --purge" || bad "profile data is deleted by --purge"

echo x > "$HOME/sentinel"
tool add Evil --app "$FAKE" --data-dir "$HOME" >/dev/null 2>&1
expect_fail "purge refuses the home folder" tool remove Evil --purge --yes
[ -f "$HOME/sentinel" ] && ok "home folder is intact" || bad "home folder is intact"
tool remove Evil >/dev/null 2>&1

mkdir -p "$DEFAULT_DATA" "$HOME/p/q/profile" "$HOME/real"
ln -s "$HOME/real" "$HOME/p/q/link"
expect_fail "safe_to_purge: the app's default profile" safe_to_purge "$DEFAULT_DATA" "$FAKE"
expect_fail "safe_to_purge: the root" safe_to_purge / "$FAKE"
expect_fail "safe_to_purge: a relative path" safe_to_purge "p/q/profile" "$FAKE"
expect_fail "safe_to_purge: a symlink" safe_to_purge "$HOME/p/q/link" "$FAKE"
expect_fail "safe_to_purge: a missing folder" safe_to_purge "$HOME/p/q/missing" "$FAKE"
expect_ok   "safe_to_purge: a dedicated profile folder" safe_to_purge "$HOME/p/q/profile" "$FAKE"

if [ "${LIVE:-0}" = 1 ]; then
  echo "== live (starts a fake app)"
  tool add Live --app "$FAKE" >/dev/null 2>&1
  if [ "$OS" = macos ]; then
    LIVE_LAUNCHER="$DEST/Fake Live.app"; LIVE_DATA="$HOME/Library/Application Support/Fake-Live"
    LIVE_PATTERN="Contents/MacOS/fake --user-data-dir=$LIVE_DATA"
    open -n "$LIVE_LAUNCHER"
  else
    LIVE_SCRIPT="$HOME/.local/share/claude-profiles/fake-live.sh"; LIVE_DATA="$HOME/.config/fake-Live"
    LIVE_PATTERN="fake --user-data-dir=$LIVE_DATA"
    "$LIVE_SCRIPT"
  fi
  pid=""
  for _ in $(seq 1 40); do pid=$(find_pid "$LIVE_DATA"); [ -n "$pid" ] && break; sleep 0.25; done
  [ -n "$pid" ] && ok "launcher starts the profile" || bad "launcher starts the profile"
  tool list | grep -q "running" && ok "list shows the profile as running" || bad "list shows the profile as running"
  if [ "$OS" = macos ]; then "$LIVE_LAUNCHER/Contents/MacOS/launch"; else "$LIVE_SCRIPT"; fi
  sleep 1
  equals "$(pgrep -f -- "$LIVE_PATTERN" | wc -l | tr -d ' ')" 1 && ok "second launch focuses instead of starting another" || bad "second launch focuses instead of starting another"
  tool launch Live >/dev/null 2>&1
  sleep 1
  equals "$(pgrep -f -- "$LIVE_PATTERN" | wc -l | tr -d ' ')" 1 && ok "'launch' subcommand does not start a duplicate" || bad "'launch' subcommand does not start a duplicate"
  expect_fail "purge refuses a running profile" tool remove Live --purge --yes
  pkill -f -- "$LIVE_PATTERN"
fi

echo
echo "$passes passed, $fails failed"
[ "$fails" = 0 ]
