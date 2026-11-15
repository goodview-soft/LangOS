#!/bin/sh
# Publie une version : ./release.sh 1.1.0 "Notes de version"
# Exporte le .pck (mise à jour légère), le zip Linux et l'APK, puis crée la release GitHub.
set -e
V="$1"; NOTES="${2:-Version $1}"
[ -n "$V" ] || { echo "usage: $0 <version> [notes]"; exit 1; }
cd "$(dirname "$0")"
REPO=goodview-soft/LangOS
GODOT="flatpak run org.godotengine.Godot"
ENGINE="$($GODOT --version | cut -d. -f1-3)"
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT" build/linux

sed -i "s/^const VERSION := .*/const VERSION := \"$V\"/" version.gd
$GODOT --headless --path . --export-pack "Linux" "$OUT/blocnote-$V.pck"
$GODOT --headless --path . --export-release "Linux" build/linux/BlocNote.x86_64
$GODOT --headless --path . --export-debug "Android" "$OUT/BlocNote-$V.apk"
cp install.sh icon.svg langos.sh langos-chat.sh langos-hotkey.sh build/linux/
rm -rf build/BlocNote && cp -r build/linux build/BlocNote
(cd build && zip -qr "release/BlocNote-$V-linux.zip" BlocNote) && rm -rf build/BlocNote

# Noms fixes pour les liens « latest » (QR code, install.sh)
cp "$OUT/BlocNote-$V.apk" "$OUT/BlocNote.apk"
cp "$OUT/BlocNote-$V-linux.zip" "$OUT/BlocNote-linux.zip"
cp install.sh "$OUT/install.sh"
rm -f "$OUT"/*.idsig

SHA="$(sha256sum "$OUT/blocnote-$V.pck" | cut -d' ' -f1)"
NAT="$(grep -o 'NATIVE := [0-9]*' version.gd | grep -o '[0-9]*$')"
cat > "$OUT/version.json" <<J
{"version": "$V", "godot": "$ENGINE", "sha256": "$SHA", "native": ${NAT:-0},
 "pck": "https://github.com/$REPO/releases/download/v$V/blocnote-$V.pck"}
J

git add -A && git commit -qm "Version $V" || true
git tag -f "v$V" && git push -q origin HEAD && git push -qf origin "v$V"
gh release create "v$V" --repo "$REPO" --title "Bloc-notes $V" --notes "$NOTES" "$OUT"/*
echo "Publié : https://github.com/$REPO/releases/tag/v$V"
