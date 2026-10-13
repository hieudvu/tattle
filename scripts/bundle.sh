#!/bin/zsh
# Assemble Tattle.app (production) or "Tattle Dev.app" (dev). The ONLY place the two
# flavours differ is the name / bundle id / executable stamped below; the production
# bundle is verified at the end to carry no dev suffix.
set -euo pipefail
cd "${0:A:h}/.."

flavor=${1:?usage: bundle.sh dev|production}
case $flavor in
  dev) name="Tattle Dev"; bundle_id="dev.hieuvd.tattle.dev"; config=debug ;;
  production) name="Tattle";     bundle_id="dev.hieuvd.tattle";     config=release ;;
  *)   echo "unknown flavor: $flavor" >&2; exit 2 ;;
esac

swift build -c $config --product Tattle
swift build -c $config --product tattle-bridge
bindir="$(swift build -c $config --show-bin-path)"
bin="$bindir/Tattle"

app="build/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
# Native-messaging host the browsers launch; same bundle => same flavour (dev/production).
cp "$bindir/tattle-bridge" "$app/Contents/MacOS/tattle-bridge"

# Browser extensions, shipped inside the app so Settings can hand the user the folder to
# "Load unpacked" (Chromium) / load temporarily (Firefox). Rebuilt from Extensions/ each time.
node scripts/build-extensions.mjs >/dev/null
mkdir -p "$app/Contents/Resources/Extensions"
cp -R Extensions/dist/chromium "$app/Contents/Resources/Extensions/chromium"
cp -R Extensions/dist/firefox "$app/Contents/Resources/Extensions/firefox"

# Sparkle (in-app updates). SwiftPM leaves the framework next to the binary instead of
# embedding it, so copy it in and teach the binary where to find it. The XPC services are
# only for sandboxed hosts; Tattle is not sandboxed, so drop them (fewer things to sign).
mkdir -p "$app/Contents/Frameworks"
ditto "$bindir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$app/Contents/Frameworks/Sparkle.framework/XPCServices" \
       "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/$name"

# Now Playing helper: loaded by Apple's /usr/bin/perl (see MediaRemoteNowPlaying), so it is a
# plain universal dylib in Resources. Missing/failed => the app just shows no titles.
clang -dynamiclib -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 -framework Foundation \
  -o "$app/Contents/Resources/libTattleNowPlaying.dylib" Helpers/NowPlaying/nowplaying.m

# macOS 26+: Resources/Tattle.icon (Icon Composer) -> Assets.car, picked via CFBundleIconName.
# macOS 15: flat Resources/Legacy.icns, picked via CFBundleIconFile.
icon_out=$(mktemp -d)
trap 'rm -rf "$icon_out"' EXIT
xcrun actool Resources/Tattle.icon --compile "$icon_out" --output-format human-readable-text \
  --notices --warnings --errors --output-partial-info-plist "$icon_out/partial.plist" \
  --app-icon Tattle --include-all-app-icons --enable-on-demand-resources NO \
  --development-region en --target-device mac --minimum-deployment-target 15.0 --platform macosx >/dev/null
cp "$icon_out/Assets.car" "$app/Contents/Resources/"
# actool's fallback icns tops out at 256px; macOS 15 gets our full-size flat icon instead.
cp Resources/Legacy.icns "$app/Contents/Resources/Tattle.icns"

# Updates are a production-only feature: a dev bundle gets no feed, so it can never update itself.
# One feed per architecture (each release publishes appcast-arm64.xml and appcast-x86_64.xml),
# so an Intel Mac is never offered the arm64 build. SUPublicEDKey is public by design.
update_keys=""
if [[ $flavor == production ]]; then
  update_arch=${UPDATE_ARCH:-$(uname -m)}
  update_feed="https://github.com/hieudvu/tattle/releases/latest/download/appcast-$update_arch.xml"
  update_keys="  <key>SUFeedURL</key><string>$update_feed</string>
  <key>SUPublicEDKey</key><string>ZHhgT8C1S0sj7qiFBFNahxlY0W+V/0YOp9V6hXCg6TI=</string>
  <key>SUEnableAutomaticChecks</key><true/>"
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>CFBundleIconFile</key><string>Tattle</string>
  <key>CFBundleIconName</key><string>Tattle</string>
  <key>NSAudioCaptureUsageDescription</key><string>Tattle mutes an app by tapping its audio so it no longer reaches the speakers. Nothing is recorded or stored.</string>
  <key>LSUIElement</key><true/>
$update_keys
</dict>
</plist>
PLIST

# Signing identity. macOS keys privacy grants (System Audio Recording, used by Mute) to the
# code signature: an ad-hoc signature changes on EVERY build, so the permission prompt came
# back after every rebuild. A real identity keeps one stable designated requirement, so the
# user grants it once. Override with SIGN_IDENTITY; falls back to ad-hoc when none is found.
if [[ -z ${SIGN_IDENTITY:-} ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ {print $2; exit}')
fi
export SIGN_IDENTITY=${SIGN_IDENTITY:--}
echo "signing with: $SIGN_IDENTITY"
# CODESIGN_FLAGS: extra codesign flags, e.g. "--options runtime --timestamp" for notarization.
# Sign inside-out, one piece at a time, never with --deep: Sparkle documents that --deep can
# clobber the signatures of its helpers, and notarization needs every Mach-O signed on its own.
sign() { codesign --force ${=CODESIGN_FLAGS:-} --sign "$SIGN_IDENTITY" "$@" >/dev/null; }
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign "$app/Contents/Resources/libTattleNowPlaying.dylib"
sign "$app/Contents/MacOS/tattle-bridge"
sign "$app"

# Safari extension (an .appex inside the app), in every flavor. It re-signs the app, so
# it must run after the signing above and before the checks below.
scripts/build-safari-extension.sh $flavor "$app"

if [[ $flavor == production ]]; then
  [[ $name == "Tattle" && $bundle_id == "dev.hieuvd.tattle" ]] || { echo "production bundle carries a dev suffix" >&2; exit 1; }
  if grep -Eq '\.dev</string>|Dev</string>' "$app/Contents/Info.plist"; then
    echo "production Info.plist contains a dev marker" >&2; exit 1
  fi
  if grep -Erq '\.dev\.safari|TattleSafari Dev' "$app/Contents/PlugIns" 2>/dev/null; then
    echo "production bundle contains a dev Safari extension" >&2; exit 1
  fi
fi
[[ -d $app/Contents/Frameworks/Sparkle.framework ]] || { echo "Sparkle.framework not embedded" >&2; exit 1; }
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist" >/dev/null 2>&1; then has_feed=1; else has_feed=0; fi
if [[ $flavor == production && $has_feed == 0 ]] || [[ $flavor == dev && $has_feed == 1 ]]; then
  echo "$flavor bundle has the wrong update feed setting" >&2; exit 1
fi
echo "built $app"
