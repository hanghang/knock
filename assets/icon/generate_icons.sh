#!/usr/bin/env bash
# Regenerates every platform launcher icon from the SVG sources in this directory.
set -euo pipefail
cd "$(dirname "$0")"

RES=../../android/app/src/main/res
APPICON=../../ios/Runner/Assets.xcassets/AppIcon.appiconset

# dpi bucket : legacy launcher px : adaptive (108dp) px
for b in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read -r dpi legacy adaptive <<<"$b"
  rsvg-convert -w "$legacy"   -h "$legacy"   app_icon.svg            -o "$RES/mipmap-$dpi/ic_launcher.png"
  rsvg-convert -w "$adaptive" -h "$adaptive" app_icon_foreground.svg -o "$RES/mipmap-$dpi/ic_launcher_foreground.png"
  rsvg-convert -w "$adaptive" -h "$adaptive" app_icon_background.svg -o "$RES/mipmap-$dpi/ic_launcher_background.png"
done

# filename : pixels (must stay in sync with Contents.json)
for e in \
  "Icon-App-20x20@1x.png:20" \
  "Icon-App-20x20@2x.png:40" \
  "Icon-App-20x20@3x.png:60" \
  "Icon-App-29x29@1x.png:29" \
  "Icon-App-29x29@2x.png:58" \
  "Icon-App-29x29@3x.png:87" \
  "Icon-App-40x40@1x.png:40" \
  "Icon-App-40x40@2x.png:80" \
  "Icon-App-40x40@3x.png:120" \
  "Icon-App-60x60@2x.png:120" \
  "Icon-App-60x60@3x.png:180" \
  "Icon-App-76x76@1x.png:76" \
  "Icon-App-76x76@2x.png:152" \
  "Icon-App-83.5x83.5@2x.png:167" \
  "Icon-App-1024x1024@1x.png:1024"
do
  rsvg-convert -w "${e##*:}" -h "${e##*:}" app_icon.svg -o "$APPICON/${e%%:*}"
done

echo "icons regenerated"
