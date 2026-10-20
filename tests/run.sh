#!/bin/bash
# Tests for claude-profiles (macOS and Linux).
# Everything runs in a throwaway HOME against a fake app that only sleeps; your
# real profiles and apps are never touched.
# LIVE=1 also starts the fake app through the generated profiles.
# BADGE=1 also draws a badged icon (needs a desktop session; takes a few seconds).

cd "$(dirname "$0")/.." || exit 1
TOOL_PATH="$PWD/claude-profiles"

passes=0
fails=0
ok()  { passes=$((passes + 1)); echo "ok   $1"; }
bad() { fails=$((fails + 1)); echo "FAIL $1"; }
expect_ok()   { local d="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
expect_fail() { local d="$1"; shift; if ( "$@" ) >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }
equals()      { [ "$1" = "$2" ]; }
is()          { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
has()         { grep -q -- "$2" "$1" 2>/dev/null; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/claude-profiles-test.XXXXXX") || exit 1
trap 'pkill -f -- "$WORK/apps" 2>/dev/null; rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/apps"
unset XDG_CONFIG_HOME XDG_DATA_HOME

# Sourcing defines the functions without running main.
. "$TOOL_PATH"
detect_os
tool() { "$TOOL_PATH" "$@"; }

# A 1x1 PNG, enough to exercise the icon conversion.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | { base64 -D 2>/dev/null || base64 -d; } > "$WORK/icon.png"

FAKE_BODY="#!/bin/bash
env | grep -E '^(CLAUDE_CONFIG_DIR|FOO)=' | sort > \"$WORK/fake.env\"
sleep 60"

if [ "$OS" = macos ]; then
  FAKE="$WORK/apps/Claude.app"
  mkdir -p "$FAKE/Contents/MacOS"
  printf '%s\n' "$FAKE_BODY" > "$FAKE/Contents/MacOS/fake"
  chmod +x "$FAKE/Contents/MacOS/fake"
  cat > "$FAKE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claude</string>
  <key>CFBundleDisplayName</key><string>Claude</string>
  <key>CFBundleExecutable</key><string>fake</string>
  <key>CFBundleIdentifier</key><string>test.fake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconName</key><string>Claude</string>
</dict></plist>
EOF
  DEST="$HOME/Applications"
  DEFAULT_DATA="$HOME/Library/Application Support/Claude"
  lpath()  { echo "$DEST/Claude $1.app"; }
  dpath()  { echo "$HOME/Library/Application Support/Claude-$1"; }
  spath()  { echo "$(lpath "$1")/Contents/MacOS/launch"; }
  PATTERN() { echo "Contents/MacOS/fake --user-data-dir=$(dpath "$1")"; }
else
  FAKE="$WORK/apps/claude-desktop"
  printf '%s\n' "$FAKE_BODY" > "$FAKE"
  chmod +x "$FAKE"
  DEST="$HOME/.local/share/applications"
  DEFAULT_DATA="$HOME/.config/claude-desktop"
  lpath()  { echo "$DEST/$(slugify "claude-desktop $1").desktop"; }
  dpath()  { echo "$HOME/.config/claude-desktop-$1"; }
  spath()  { echo "$HOME/.local/share/claude-profiles/$(slugify "claude-desktop $1").sh"; }
  PATTERN() { echo "claude-desktop --user-data-dir=$(dpath "$1")"; }
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
expect_ok   "env: NAME=VALUE accepted" check_env_pair FOO=bar
expect_ok   "env: empty value accepted" check_env_pair FOO=
expect_fail "env: missing = rejected" check_env_pair FOO
expect_fail "env: bad name rejected" check_env_pair "F-O=bar"

equals "$(normalize_color blue)" 3b82f6 && ok "color: names are understood" || bad "color: names are understood"
equals "$(normalize_color '#FF8800')" ff8800 && ok "color: hex is normalised" || bad "color: hex is normalised"
expect_fail "color: grey is refused" normalize_color 808080
expect_fail "color: bad hex is refused" normalize_color zzzzzz
expect_fail "color: short hex is refused" normalize_color fff
expect_fail "color: unknown name is refused" normalize_color chartreuse

equals "$(absolute_path /a/b/)" /a/b && ok "absolute_path strips trailing slash" || bad "absolute_path strips trailing slash"
equals "$(absolute_path /)" / && ok "absolute_path keeps the root" || bad "absolute_path keeps the root"
expect_fail "absolute_path rejects .." absolute_path /a/../b
equals "$(slugify 'Fake Work')" fake-work && ok "slugify" || bad "slugify"

echo "== add"
tool add Work --app "$FAKE" --no-badge --dry-run >"$WORK/dry.out" 2>&1
has "$WORK/dry.out" "would create" && [ ! -e "$DEST" ] && ok "dry run prints the plan and writes nothing" || bad "dry run prints the plan and writes nothing"

INFO_BEFORE=$(find "$FAKE" -type f | sort | xargs shasum | shasum)
expect_ok "add creates a profile" tool add Work --app "$FAKE" --no-badge --env FOO=bar --config-dir "$HOME/.cfg-work"
[ -e "$(lpath Work)" ] && ok "profile exists" || bad "profile exists"
equals "$(find "$FAKE" -type f | sort | xargs shasum | shasum)" "$INFO_BEFORE" && ok "the original app is untouched" || bad "the original app is untouched"

if [ "$OS" = macos ]; then
  B="$(lpath Work)"
  INFO="$B/Contents/Info.plist"
  equals "$(plist_get "$INFO" CFBundleDisplayName)" "Claude Work" && ok "copy has its own display name" || bad "copy has its own display name"
  equals "$(plist_get "$INFO" CFBundleIdentifier)" "local.claude-profiles.claude-work" && ok "copy has its own bundle id" || bad "copy has its own bundle id"
  equals "$(plist_get "$INFO" CFBundleName)" "Claude" && ok "bundle name is kept (Electron needs it for helpers)" || bad "bundle name is kept (Electron needs it for helpers)"
  equals "$(plist_get "$INFO" CFBundleExecutable)" "profile-launch" && ok "copy starts through the profile entry point" || bad "copy starts through the profile entry point"
  expect_ok "copy is validly signed" codesign --verify --deep --strict "$B"
  expect_ok "entry point is valid bash" bash -n "$B/Contents/MacOS/profile-launch"
  has "$B/Contents/MacOS/profile-launch" "CLAUDE_CONFIG_DIR" && has "$B/Contents/MacOS/profile-launch" "FOO=bar" && ok "entry point sets the environment" || bad "entry point sets the environment"
  has "$B/Contents/MacOS/profile-launch" -- "--user-data-dir=" && ok "entry point passes the data folder" || bad "entry point passes the data folder"
  expect_ok "Info.plist is valid" plutil -lint "$INFO"
  [ ! -e "$B/Contents/Resources/profile.icns" ] && ok "--no-badge keeps the app's own icon" || bad "--no-badge keeps the app's own icon"
  equals "$(conf_get "$B/Contents/Resources/profile.conf" MODE)" copy && ok "conf records the mode" || bad "conf records the mode"
  equals "$(conf_get "$B/Contents/Resources/profile.conf" DATA_DIR)" "$(dpath Work)" && ok "profile folder sits next to the default one" || bad "profile folder sits next to the default one"
else
  has "$(lpath Work)" '^Exec=' && equals "$(conf_get "$(lpath Work)" X-ClaudeProfiles-DATA_DIR)" "$(dpath Work)" && ok ".desktop entry has Exec and profile folder" || bad ".desktop entry has Exec and profile folder"
  expect_ok "launch script is valid bash" bash -n "$(spath Work)"
fi

echo "== icon"
expect_ok "add with a custom PNG icon" tool add Iconic --app "$FAKE" --icon "$WORK/icon.png" --no-config-dir
if [ "$OS" = macos ]; then
  I="$(lpath Iconic)"
  [ -s "$I/Contents/Resources/profile.icns" ] && ok "PNG is converted to an icns" || bad "PNG is converted to an icns"
  equals "$(plist_get "$I/Contents/Info.plist" CFBundleIconFile)" "profile.icns" && ok "copy points at the custom icon" || bad "copy points at the custom icon"
  [ -z "$(plist_get "$I/Contents/Info.plist" CFBundleIconName)" ] && ok "the app's built-in icon name is removed" || bad "the app's built-in icon name is removed"
  expect_ok "copy with a custom icon is validly signed" codesign --verify --deep --strict "$I"
  ! has "$I/Contents/MacOS/profile-launch" CLAUDE_CONFIG_DIR && ok "--no-config-dir sets no config folder" || bad "--no-config-dir sets no config folder"
fi
expect_fail "a missing icon file is refused" tool add Missing --app "$FAKE" --icon "$WORK/nope.png"
[ ! -e "$(lpath Missing)" ] && ok "failed add leaves nothing behind" || bad "failed add leaves nothing behind"
tool remove Iconic >/dev/null 2>&1

echo "== config folder (macOS, app named Claude)"
if [ "$OS" = macos ]; then
  tool add Cfg --app "$FAKE" --no-badge >"$WORK/cfg.out" 2>&1
  has "$(lpath Cfg)/Contents/MacOS/profile-launch" "CLAUDE_CONFIG_DIR=$HOME/.claude-cfg" && ok "default config folder is ~/.claude-<label in lowercase>" || bad "default config folder is ~/.claude-<label in lowercase>"
  expect_fail "~/.claude itself is refused" tool add Bad --app "$FAKE" --config-dir "$HOME/.claude"
  tool env Cfg >"$WORK/env.out" 2>&1
  has "$WORK/env.out" "^export CLAUDE_CONFIG_DIR=" && ok "env prints export lines" || bad "env prints export lines"
  tool remove Cfg >/dev/null 2>&1
fi
expect_fail "an unusable --color is refused" tool add Grey --app "$FAKE" --color grey
expect_fail "the app's default profile is refused" tool add Main --app "$FAKE" --data-dir "$DEFAULT_DATA"
expect_fail "bad label is rejected" tool add "bad/label" --app "$FAKE"
expect_fail "missing app is refused" tool add Work --app "$WORK/nope"
expect_fail "invalid --env is refused" tool add E --app "$FAKE" --env nope

if [ "$OS" = macos ]; then
  mkdir -p "$DEST/Claude Foreign.app"
  expect_fail "does not overwrite a foreign app" tool add Foreign --app "$FAKE" --no-badge
  [ -d "$DEST/Claude Foreign.app" ] && ok "foreign app is untouched" || bad "foreign app is untouched"
fi

echo "== shared mode"
expect_ok "add --shared-app creates a launcher" tool add Shared --app "$FAKE" --env FOO=shared --shared-app
S="$(spath Shared)"
[ -x "$S" ] && ok "launch script is executable" || bad "launch script is executable"
expect_ok "launch script is valid bash" bash -n "$S"
tail -n 1 "$S" | grep -q '^launch_profile ' && ok "launch script ends by launching the profile" || bad "launch script ends by launching the profile"
tail -n 1 "$S" | grep -q 'FOO=shared' && ok "launch script passes the environment" || bad "launch script passes the environment"
has "$S" '^match_main_pid' && ok "launch script is self-contained" || bad "launch script is self-contained"
tool remove Shared >/dev/null 2>&1

echo "== list / update"
tool list >"$WORK/list.out" 2>&1
has "$WORK/list.out" "^Work" && has "$WORK/list.out" "stopped" && has "$WORK/list.out" "FOO=bar" && ok "list shows the profile, its state and env" || bad "list shows the profile, its state and env"
tool list --dest "$WORK/empty" 2>&1 | grep -q "no profiles" && ok "list on an empty folder" || bad "list on an empty folder"
expect_ok "adding again regenerates the profile" tool add Work --app "$FAKE" --no-badge --env FOO=bar --config-dir "$HOME/.cfg-work"
if [ "$OS" = macos ]; then
  expect_ok "update rebuilds the copy" tool update Work
  expect_ok "updated copy is validly signed" codesign --verify --deep --strict "$(lpath Work)"
  has "$(lpath Work)/Contents/MacOS/profile-launch" "FOO=bar" && ok "update keeps the environment" || bad "update keeps the environment"
  tool add Pic --app "$FAKE" --icon "$WORK/icon.png" --no-config-dir >/dev/null 2>&1
  tool update Pic >/dev/null 2>&1
  [ -s "$(lpath Pic)/Contents/Resources/profile.icns" ] && ok "update keeps the custom icon" || bad "update keeps the custom icon"
  tool remove Pic >/dev/null 2>&1
  expect_fail "update of an unknown label fails" tool update Nope
else
  expect_fail "update is macOS-only" tool update Work
fi

echo "== remove"
mkdir -p "$(dpath Work)" "$HOME/.cfg-work"; echo x > "$(dpath Work)/Local State"; echo x > "$HOME/.cfg-work/settings.json"
expect_ok "remove deletes the profile" tool remove Work
[ ! -e "$(lpath Work)" ] && ok "profile is gone" || bad "profile is gone"
[ -f "$(dpath Work)/Local State" ] && [ -f "$HOME/.cfg-work/settings.json" ] && ok "data and config are kept by default" || bad "data and config are kept by default"
expect_fail "remove of an unknown label fails" tool remove Work

tool add Work --app "$FAKE" --no-badge --config-dir "$HOME/.cfg-work" >/dev/null 2>&1
expect_fail "purge without a terminal or --yes is refused" tool remove Work --purge </dev/null
[ -f "$(dpath Work)/Local State" ] && ok "refused purge deletes nothing" || bad "refused purge deletes nothing"
expect_ok "purge with --yes" tool remove Work --purge --yes
[ ! -e "$(dpath Work)" ] && [ ! -e "$HOME/.cfg-work" ] && ok "--purge deletes the data and the config folder" || bad "--purge deletes the data and the config folder"

tool add Never --app "$FAKE" --no-badge --config-dir "$HOME/.cfg-never" >/dev/null 2>&1
expect_ok "purge works when the profile never created its folders" tool remove Never --purge --yes
[ ! -e "$(lpath Never)" ] && ok "profile is removed even though there was nothing to purge" || bad "profile is removed even though there was nothing to purge"

echo x > "$HOME/sentinel"
tool add Evil --app "$FAKE" --no-badge --data-dir "$HOME" --no-config-dir >/dev/null 2>&1
expect_fail "purge refuses the home folder" tool remove Evil --purge --yes
[ -f "$HOME/sentinel" ] && ok "home folder is intact" || bad "home folder is intact"
tool remove Evil >/dev/null 2>&1

mkdir -p "$DEFAULT_DATA" "$HOME/.claude" "$HOME/p/q/profile" "$HOME/real"
ln -s "$HOME/real" "$HOME/p/q/link"
expect_fail "safe_to_purge: the app's default profile" safe_to_purge "$DEFAULT_DATA" "$FAKE"
expect_fail "safe_to_purge: ~/.claude" safe_to_purge "$HOME/.claude" "$FAKE"
expect_fail "safe_to_purge: the root" safe_to_purge / "$FAKE"
expect_fail "safe_to_purge: a relative path" safe_to_purge "p/q/profile" "$FAKE"
expect_fail "safe_to_purge: a symlink" safe_to_purge "$HOME/p/q/link" "$FAKE"
expect_fail "safe_to_purge: a missing folder" safe_to_purge "$HOME/p/q/missing" "$FAKE"
expect_ok   "safe_to_purge: a dedicated profile folder" safe_to_purge "$HOME/p/q/profile" "$FAKE"

if [ "${BADGE:-0}" = 1 ] || [ "${LIVE:-0}" = 1 ]; then
  if [ "$OS" = macos ]; then
    echo "== badge (draws an icon)"
    tool add Badge --app "$FAKE" --no-config-dir >/dev/null 2>&1
    [ -s "$(lpath Badge)/Contents/Resources/profile.icns" ] && ok "default icon is the app's icon with a badge" || bad "default icon is the app's icon with a badge"
    tool remove Badge >/dev/null 2>&1

    # The fake app's own icon is grey, which has no hue to turn: --color falls back to a badge.
    tool add Greyed --app "$FAKE" --color blue --no-config-dir >"$WORK/grey.out" 2>&1
    [ -s "$(lpath Greyed)/Contents/Resources/profile.icns" ] && has "$WORK/grey.out" "no colour to change" && ok "--color on a grey icon falls back to a badge and says so" || bad "--color on a grey icon falls back to a badge and says so"
    tool remove Greyed >/dev/null 2>&1

    # Give the fake app a coloured icon, as real apps have.
    osascript -l JavaScript -e 'ObjC.import("AppKit"); function run(a) { const img = $.NSImage.alloc.initWithSize($.NSMakeSize(1024, 1024)); img.lockFocus; $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.85, 0.45, 0.3, 1).setFill; $.NSBezierPath.fillRect($.NSMakeRect(0, 0, 1024, 1024)); $.NSColor.whiteColor.setFill; $.NSBezierPath.bezierPathWithOvalInRect($.NSMakeRect(312, 312, 400, 400)).fill; img.unlockFocus; $.NSBitmapImageRep.imageRepWithData(img.TIFFRepresentation).representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $.NSDictionary.dictionary).writeToFileAtomically($(a[0]), true); return "ok"; }' "$WORK/color.png" >/dev/null 2>&1
    mkdir -p "$FAKE/Contents/Resources"
    make_icns "$WORK/color.png" "$FAKE/Contents/Resources/fake.icns"
    plist_set "$FAKE/Contents/Info.plist" CFBundleIconFile fake.icns
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$FAKE/Contents/Info.plist" >/dev/null 2>&1
    touch "$FAKE"

    # Hue (0-359) of the pixel left of the icon's centre, where the tile is plain.
    hue_of_icns() {
      sips -s format png "$1" --out "$WORK/hue.png" >/dev/null 2>&1 || return 1
      osascript -l JavaScript -e 'ObjC.import("AppKit"); function run(a) { const r = $.NSBitmapImageRep.imageRepWithData($.NSData.dataWithContentsOfFile($(a[0]))); const c = r.colorAtXY(Math.round(r.pixelsWide * 0.06), Math.round(r.pixelsHigh / 2)).colorUsingColorSpace($.NSColorSpace.sRGBColorSpace); return String(Math.round(c.hueComponent * 360)); }' "$WORK/hue.png"
    }
    tool add Tint --app "$FAKE" --color blue --no-config-dir >/dev/null 2>&1
    hue=$(hue_of_icns "$(lpath Tint)/Contents/Resources/profile.icns")
    [ -n "$hue" ] && [ "$hue" -ge 207 ] && [ "$hue" -le 227 ] && ok "--color turns the whole icon to the chosen hue (got $hue, wanted ~217)" || bad "--color turns the whole icon to the chosen hue (got '$hue', wanted ~217)"
    tool remove Tint >/dev/null 2>&1
    tool add Tint --app "$FAKE" --color 22c55e --no-config-dir >/dev/null 2>&1
    hue=$(hue_of_icns "$(lpath Tint)/Contents/Resources/profile.icns")
    [ -n "$hue" ] && [ "$hue" -ge 132 ] && [ "$hue" -le 152 ] && ok "--color works for another hue (got $hue, wanted ~142)" || bad "--color works for another hue (got '$hue', wanted ~142)"
    tool remove Tint >/dev/null 2>&1
  fi
fi

if [ "${LIVE:-0}" = 1 ]; then
  echo "== live (starts the fake app)"
  wait_for_pid() { local p="" i; for i in $(seq 1 40); do p=$(find_pid "$1"); [ -n "$p" ] && break; sleep 0.25; done; echo "$p"; }
  count() { pgrep -f -- "$(PATTERN "$1")" | wc -l | tr -d ' '; }

  tool add Live --app "$FAKE" --no-badge --env FOO=live --config-dir "$HOME/.cfg-live" >/dev/null 2>&1
  rm -f "$WORK/fake.env"
  tool launch Live
  pid=$(wait_for_pid "$(dpath Live)")
  [ -n "$pid" ] && ok "'launch' starts the profile" || bad "'launch' starts the profile"
  sleep 1
  has "$WORK/fake.env" "FOO=live" && has "$WORK/fake.env" "CLAUDE_CONFIG_DIR=$HOME/.cfg-live" && ok "the app receives its environment" || bad "the app receives its environment"
  tool list | grep -q "running" && ok "list shows the profile as running" || bad "list shows the profile as running"
  tool launch Live >/dev/null 2>&1
  sleep 1
  equals "$(count Live)" 1 && ok "a second launch does not start a duplicate" || bad "a second launch does not start a duplicate"
  expect_fail "remove refuses a running profile" tool remove Live
  expect_fail "update refuses a running profile" tool update Live
  pkill -f -- "$(PATTERN Live)"; sleep 1
  tool remove Live >/dev/null 2>&1

  tool add LiveShared --app "$FAKE" --env FOO=shared --shared-app >/dev/null 2>&1
  rm -f "$WORK/fake.env"
  if [ "$OS" = macos ]; then open -n "$(lpath LiveShared)"; else "$(spath LiveShared)"; fi
  pid=$(wait_for_pid "$(dpath LiveShared)")
  [ -n "$pid" ] && ok "a shared-app launcher starts the profile" || bad "a shared-app launcher starts the profile"
  sleep 1
  has "$WORK/fake.env" "FOO=shared" && ok "a shared-app launcher passes the environment" || bad "a shared-app launcher passes the environment"
  if [ "$OS" = macos ]; then "$(spath LiveShared)"; else "$(spath LiveShared)"; fi
  sleep 1
  equals "$(count LiveShared)" 1 && ok "a shared-app launcher focuses instead of duplicating" || bad "a shared-app launcher focuses instead of duplicating"
  pkill -f -- "$(PATTERN LiveShared)"
fi

echo
echo "$passes passed, $fails failed"
[ "$fails" = 0 ]
