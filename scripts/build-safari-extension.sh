#!/bin/zsh
# Build the Safari Web Extension app extension (.appex) and embed it in an already-built Tattle app.
#
#   scripts/build-safari-extension.sh <dev|pro> <path/to/Tattle[ Dev].app>
#
# Produces <app>/Contents/PlugIns/TattleSafari[ Dev].appex and re-signs the app (the app's seal
# covers PlugIns/, so embedding invalidates the signature bundle.sh made).
# No Xcode project: swiftc + a hand-assembled bundle + codesign. See Extensions/safari/README.md.
#
# Env: SIGN_IDENTITY  codesign identity (default "-" = ad-hoc)
#      CODESIGN_FLAGS extra codesign flags (e.g. "--options runtime --timestamp" for notarization)
#      ARCHS          space-separated (default: this machine's arch; "arm64 x86_64" for universal)
set -euo pipefail
root=${0:A:h:h}
cd "$root"

flavor=${1:?usage: build-safari-extension.sh dev|pro <path/to/Tattle.app>}
app=${2:?usage: build-safari-extension.sh dev|pro <path/to/Tattle.app>}
case $flavor in
  dev) appex_name="TattleSafari Dev"; suffix=".dev" ;;
  pro) appex_name="TattleSafari";     suffix="" ;;
  *)   echo "unknown flavor: $flavor" >&2; exit 2 ;;
esac
app=${app:A}
[[ -d $app && -f $app/Contents/Info.plist ]] || { echo "not an app bundle: $app" >&2; exit 2; }

parent_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
want_parent="dev.hieuvd.tattle$suffix"
[[ $parent_id == $want_parent ]] || { echo "flavor $flavor needs bundle id $want_parent, app has $parent_id" >&2; exit 1; }
appex_id="$parent_id.safari"
parent_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
parent_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
support_dir=$([[ $flavor == pro ]] && echo "Tattle" || echo "Tattle Dev")
sign=${SIGN_IDENTITY:--}
archs=(${=ARCHS:-$(uname -m)})

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
appex="$work/$appex_name.appex"
mkdir -p "$appex/Contents/MacOS" "$appex/Contents/Resources"

# 1. Web extension resources: wrapper + shared core + icons (same layout as Extensions/dist/*).
res="$appex/Contents/Resources"
cp Extensions/safari/manifest.json Extensions/safari/background.js "$res/"
cp -R Extensions/icons "$res/icons"
mkdir -p "$res/core"
cp -R Extensions/core/src "$res/core/src"
/usr/bin/python3 - "$res/manifest.json" <<'PY'
import json, sys, os
m = json.load(open(sys.argv[1])); root = os.path.dirname(sys.argv[1])
assert m["manifest_version"] == 3 and m["name"] == "Tattle"
for p in ("tabs", "nativeMessaging", "scripting", "alarms"): assert p in m["permissions"], p
for f in list(m["icons"].values()) + m["background"]["scripts"]: assert os.path.exists(os.path.join(root, f)), f
PY

# 2. The handler: one binary per arch, entered through NSExtensionMain (an appex has no main()).
bins=()
for arch in $archs; do
  out="$work/handler-$arch"
  swiftc -swift-version 6 -O -parse-as-library -module-name TattleSafari \
    -target "$arch-apple-macos15.0" -application-extension \
    -framework SafariServices -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$out" Extensions/safari/App/*.swift
  bins+=("$out")
done
if (( ${#bins} > 1 )); then lipo -create "${bins[@]}" -output "$appex/Contents/MacOS/$appex_name"
else cp "${bins[1]}" "$appex/Contents/MacOS/$appex_name"; fi

# 3. Info.plist. TattleFlavour is what the handler reads to pick its socket: dev can never reach pro.
cat > "$appex/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$appex_name</string>
  <key>CFBundleDisplayName</key><string>Tattle${suffix:+ Dev}</string>
  <key>CFBundleIdentifier</key><string>$appex_id</string>
  <key>CFBundleExecutable</key><string>$appex_name</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$parent_version</string>
  <key>CFBundleVersion</key><string>$parent_build</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>TattleFlavour</key><string>$flavor</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.Safari.web-extension</string>
    <key>NSExtensionPrincipalClass</key><string>SafariWebExtensionHandler</string>
  </dict>
</dict>
</plist>
PLIST
plutil -lint "$appex/Contents/Info.plist" >/dev/null

# 4. Entitlements. App Sandbox is mandatory for an appex. It reaches the (unsandboxed) app through
#    its Unix socket, not an App Group: group containers need a team-prefixed id (no ad-hoc / dev
#    builds) and the app already owns this socket for Chrome/Firefox. The sandbox exceptions allow
#    exactly that one directory/socket. Fine for Developer ID; NOT acceptable for the Mac App Store.
cat > "$work/appex.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
  <array><string>/Library/Application Support/$support_dir/</string></array>
  <key>com.apple.security.temporary-exception.sbpl</key>
  <string>(allow network-outbound (regex #"^/Users/[^/]+/Library/Application Support/$support_dir/bridge\.sock\$"))</string>
</dict>
</plist>
PLIST
plutil -lint "$work/appex.entitlements" >/dev/null

# 5. Embed, then sign inside-out: appex first, then the app (without --deep, keeping its own flags).
codesign --force ${=CODESIGN_FLAGS:-} --sign "$sign" --entitlements "$work/appex.entitlements" "$appex" >/dev/null
rm -rf "$app/Contents/PlugIns/$appex_name.appex"
mkdir -p "$app/Contents/PlugIns"
cp -R "$appex" "$app/Contents/PlugIns/"
codesign --force ${=CODESIGN_FLAGS:-} --sign "$sign" "$app" >/dev/null
codesign --verify --deep --strict "$app"
echo "built $app/Contents/PlugIns/$appex_name.appex ($appex_id)"
