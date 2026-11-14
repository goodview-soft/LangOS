#!/bin/sh
# Installe Bloc-notes pour l'utilisateur courant (sans mot de passe) :
#   curl -fsSL https://github.com/goodview-soft/LangOS/releases/latest/download/install.sh | sh
# Désinstaller : sh install.sh --uninstall
set -e
APP="$HOME/.local/share/blocnote"
BIN="$HOME/.local/bin/blocnote"
DESK="$HOME/.local/share/applications/blocnote.desktop"
URL="https://github.com/goodview-soft/LangOS/releases/latest/download/BlocNote-linux.zip"

if [ "$1" = "--uninstall" ]; then
	rm -rf "$APP" "$BIN" "$DESK"
	echo "Bloc-notes désinstallé."
	exit 0
fi

mkdir -p "$APP" "$(dirname "$BIN")" "$(dirname "$DESK")"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -f "$HERE/BlocNote.x86_64" ]; then
	SRC="$HERE"                        # lancé depuis le zip décompressé
else
	command -v unzip >/dev/null || { echo "Installer d'abord unzip (sudo apt install unzip)."; exit 1; }
	TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
	echo "Téléchargement…"
	curl -fsSL -o "$TMP/sl.zip" "$URL"
	unzip -q "$TMP/sl.zip" -d "$TMP"
	SRC="$TMP/BlocNote"
fi
cp -f "$SRC"/BlocNote.x86_64 "$SRC"/icon.svg "$SRC"/install.sh "$APP"/
chmod +x "$APP/BlocNote.x86_64"
ln -sf "$APP/BlocNote.x86_64" "$BIN"
cat > "$DESK" <<D
[Desktop Entry]
Type=Application
Name=Bloc-notes
Comment=Bloc-notes avec clavier visuel
Exec=$APP/BlocNote.x86_64
Icon=$APP/icon.svg
Terminal=false
Categories=Utility;TextEditor;
D
command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESK")" 2>/dev/null || true
echo "Bloc-notes installé : menu des applications, ou commande « blocnote »."
