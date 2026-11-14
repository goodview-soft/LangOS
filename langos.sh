#!/bin/sh
# Lance LangOS. Prépare l'audio pour Sound Link : la sortie du PC (monitor) devient l'entrée « Default »,
# et un micro virtuel « Sound-Link-Micro » reçoit les micros des clients.
DIR="$(cd "$(dirname "$0")" && pwd)"
SINK="$(pactl get-default-sink 2>/dev/null)"
SRC="$(pactl get-default-source 2>/dev/null)"
if command -v pactl >/dev/null && ! pactl list short sinks 2>/dev/null | grep -q soundlink_sink; then
	pactl load-module module-null-sink sink_name=soundlink_sink sink_properties=device.description=Sound-Link-Sortie >/dev/null
	pactl load-module module-remap-source master=soundlink_sink.monitor source_name=soundlink_mic source_properties=device.description=Sound-Link-Micro >/dev/null
	[ -n "$SINK" ] && pactl set-default-sink "$SINK"
	[ -n "$SRC" ] && pactl set-default-source "$SRC"
fi
[ -n "$SINK" ] && export PULSE_SOURCE="${SINK}.monitor"
if [ -x "$DIR/BlocNote.x86_64" ]; then
	exec "$DIR/BlocNote.x86_64" --audio-driver PulseAudio "$@"
fi
exec flatpak run --env=PULSE_SOURCE="$PULSE_SOURCE" org.godotengine.Godot --audio-driver PulseAudio --path "$DIR" "$@"
