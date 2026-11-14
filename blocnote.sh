#!/bin/sh
exec flatpak run org.godotengine.Godot --path "$(cd "$(dirname "$0")" && pwd)" "$@"
