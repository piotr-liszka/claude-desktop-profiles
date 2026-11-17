#!/bin/bash
# Builds the menu bar app for claude-profiles and puts it in ~/Applications.
# Needs Apple's Swift compiler (Xcode or the Command Line Tools) and macOS 13 or later.
# The app carries its own copy of ../claude-profiles and does all its work through it.

NAME="Claude Profiles Menu"
BUNDLE_ID="local.claude-profiles.menubar"
EXE="ProfilesMenu"

die() { echo "build.sh: $*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: menubar/build.sh [--dest DIR] [--open] [--universal]

Builds "$NAME.app" into DIR (default ~/Applications) from the Swift sources next
to this script, with a copy of claude-profiles inside it.
  --dest DIR   where to put the app
  --open       open it when it is built
  --universal  build for both Apple silicon and Intel (for releases)
Run it again after you change claude-profiles or the sources.
USAGE
}

here="$(cd "$(dirname "$0")" && pwd)" || exit 1
tool="$here/../claude-profiles"
dest="$HOME/Applications"
open_it=0
universal=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) [ $# -ge 2 ] || die "--dest needs a value"; dest="$2"; shift 2 ;;
    --open) open_it=1; shift ;;
    --universal) universal=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac
done
case "$dest" in /*) ;; *) dest="$PWD/$dest" ;; esac
case "$dest" in */../* | */..) die "--dest must not contain '..'" ;; esac

[ "$(uname -s)" = Darwin ] || die "the menu bar app is macOS-only"
command -v swiftc >/dev/null || die "swiftc not found. Install Apple's Command Line Tools with: xcode-select --install"
[ -f "$tool" ] || die "cannot find $tool"

bundle="$dest/$NAME.app"
tmp="$dest/.$NAME.app.partial"
if [ -e "$bundle" ] && [ ! -f "$bundle/Contents/Resources/menubar.conf" ]; then
  die "'$bundle' exists and was not created by this script; refusing to overwrite it"
fi
version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$tool" | head -n 1)

mkdir -p "$dest" || die "cannot create $dest"
rm -rf "$tmp"
mkdir -p "$tmp/Contents/MacOS" "$tmp/Contents/Resources" || die "cannot create $tmp"

if [ "$universal" = 1 ]; then archs="arm64 x86_64"; else archs="$(uname -m)"; fi
slices=()
for arch in $archs; do
  echo "Compiling for $arch..." >&2
  if ! swiftc -O -swift-version 5 -parse-as-library \
      -target "$arch-apple-macos13.0" \
      -o "$tmp/$EXE-$arch" "$here"/Sources/*.swift; then
    rm -rf "$tmp"
    die "compiling failed"
  fi
  slices[${#slices[@]}]="$tmp/$EXE-$arch"
done
lipo -create "${slices[@]}" -output "$tmp/Contents/MacOS/$EXE" || { rm -rf "$tmp"; die "could not combine the builds"; }
rm -f "${slices[@]}"

cp "$tool" "$tmp/Contents/Resources/claude-profiles" && chmod +x "$tmp/Contents/Resources/claude-profiles" ||
  { rm -rf "$tmp"; die "cannot copy claude-profiles"; }

# The same badged icon the updater app gets, drawn by claude-profiles itself. Optional.
icon_key=""
if bash -c '. "$1"; detect_os; app=$(default_app) && badge_icns "$app" "$2" Menu ""' _ "$tool" "$tmp/Contents/Resources/icon.icns" 2>/dev/null &&
  [ -s "$tmp/Contents/Resources/icon.icns" ]; then
  icon_key='  <key>CFBundleIconFile</key><string>icon</string>'
fi

cat > "$tmp/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
$icon_key
</dict>
</plist>
PLIST
echo "CREATED_BY=claude-profiles menubar/build.sh $version" > "$tmp/Contents/Resources/menubar.conf"

codesign --force --deep --sign - "$tmp" >/dev/null 2>&1 || { rm -rf "$tmp"; die "could not sign the app"; }

# Replace a running copy: quit it first, as its Quit menu would.
if pgrep -f "$bundle/Contents/MacOS/$EXE" >/dev/null 2>&1; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$bundle/Contents/MacOS/$EXE" >/dev/null 2>&1 || break; sleep 0.5; done
  open_it=1
fi
rm -rf "$bundle"
mv "$tmp" "$bundle" || die "could not move the app into place"
touch "$bundle"
echo "Built: $bundle"
if [ "$open_it" = 1 ]; then open "$bundle"; else echo "Open it to add its icon to the menu bar."; fi
