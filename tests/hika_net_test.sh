#!/bin/sh
# Test de bouclage LAN Hikabrain : un hôte et un client (127.0.0.1), deux processus Godot headless.
# Vérifie connexion, apparition des joueurs, déplacement répliqué, blocs posés répliqués (dans les deux sens),
# scores synchronisés et déconnexion propre. Usage : tests/hika_net_test.sh [port]
DIR="$(cd "$(dirname "$0")/.." && pwd)"; PORT=${1:-17779}
G="flatpak run org.godotengine.Godot --headless --path $DIR res://games/hikabrain/scenes/game.tscn --"
$G --hb-net-host=$PORT > /tmp/hika_net_host.log 2>&1 & HP=$!
sleep 10
timeout 100 $G --hb-net-join=127.0.0.1:$PORT > /tmp/hika_net_client.log 2>&1; CR=$?
wait $HP; HR=$?
grep -h HBTEST /tmp/hika_net_host.log /tmp/hika_net_client.log
[ $CR -eq 0 ] && [ $HR -eq 0 ] && echo "HIKA-NET : SUCCES" && exit 0
echo "HIKA-NET : ECHEC (client=$CR hote=$HR)"; exit 1
