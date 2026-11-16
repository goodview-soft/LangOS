#!/bin/sh
# Test de bouclage LAN Deep Miner : un hôte et un client (127.0.0.1), deux processus Godot headless.
DIR="$(cd "$(dirname "$0")/.." && pwd)"; PORT=${1:-17778}
G="flatpak run org.godotengine.Godot --headless --path $DIR res://games/deepminer/main.tscn --"
$G --dm-net-host=$PORT > /tmp/dm_net_host.log 2>&1 & HP=$!
sleep 14
timeout 100 $G --dm-net-join=127.0.0.1:$PORT > /tmp/dm_net_client.log 2>&1; CR=$?
wait $HP; HR=$?
grep -h NETTEST /tmp/dm_net_host.log /tmp/dm_net_client.log
[ $CR -eq 0 ] && [ $HR -eq 0 ] && echo "NET : SUCCES" && exit 0
echo "NET : ECHEC (client=$CR hote=$HR)"; exit 1
