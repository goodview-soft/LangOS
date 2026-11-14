#!/bin/bash
# Crée un raccourci clavier GLOBAL (Cinnamon) qui ouvre l'overlay chat de LangOS, même dans un jeu.
# Usage : ./langos-hotkey.sh [raccourci]      ex. '<Super>minus' (défaut), '<Alt>minus', 'Pause'
# Attention : un raccourci sur la touche « - » seule désactiverait la touche - partout dans le système.
set -e
BIND="${1:-<Super>minus}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/langos-chat.sh"
KEY=langos-chat
P="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/$KEY/"
gsettings set "$P" name 'LangOS chat'
gsettings set "$P" command "$CMD"
gsettings set "$P" binding "['$BIND']"
LIST="$(gsettings get org.cinnamon.desktop.keybindings custom-list)"
case "$LIST" in
	*"'$KEY'"*) ;;
	"@as []"|"[]") gsettings set org.cinnamon.desktop.keybindings custom-list "['$KEY']" ;;
	*) gsettings set org.cinnamon.desktop.keybindings custom-list "${LIST%]*}, '$KEY']" ;;
esac
echo "Raccourci $BIND → $CMD"
