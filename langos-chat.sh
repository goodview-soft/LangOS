#!/bin/bash
# Ouvre / ferme l'overlay chat IA de LangOS (LangOS doit être lancé). À associer à un raccourci clavier global.
printf 'toggle-chat' > /dev/udp/127.0.0.1/4360
