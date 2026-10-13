#!/bin/zsh
# Regenerate Resources/Legacy.icns (the macOS 15 icon) from design/icons/app-icon.svg.
# macOS 26+ uses the Liquid Glass icon compiled from Resources/Tattle.icon instead.
# Dev tool: needs a Chromium browser (Edge or Chrome) to rasterise the SVG.
# The generated .icns is committed, so builds do NOT need this.
set -euo pipefail
cd "${0:A:h}/.."

browser=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
  [[ -x $c ]] && browser=$c && break
done
[[ -n $browser ]] || { echo "need Chrome or Edge to rasterise the SVG" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
print "<html><body style='margin:0;background:transparent'><img src='file://$PWD/design/icons/app-icon.svg' width=1024 height=1024></body></html>" > "$work/page.html"
"$browser" --headless=new --mute-audio --no-first-run --user-data-dir="$work/profile" \
  --hide-scrollbars --default-background-color=00000000 --window-size=1024,1024 \
  --screenshot="$work/icon.png" "file://$work/page.html" >/dev/null 2>&1

set=$work/AppIcon.iconset; mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$work/icon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$work/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/Legacy.icns
echo "wrote Resources/Legacy.icns"
