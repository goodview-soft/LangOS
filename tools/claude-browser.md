# Piloter le navigateur LangOS avec Claude Code

1. Dans LangOS : Logiciels > Chromium, coche « Claude Code », puis relance LangOS (le port ne s'applique qu'au démarrage).
2. Un voyant rouge « piloté (port 9222) » apparaît. Le port n'écoute qu'en local (127.0.0.1) : tout programme de la machine peut alors piloter le navigateur et voir tes sessions connectées. Décoche quand tu n'en as pas besoin.
3. Dans un terminal : `claude mcp add langos-browser -- npx chrome-devtools-mcp@latest --browser-url=http://127.0.0.1:9222`
4. Dans Claude Code, demande par exemple « ouvre example.com dans le navigateur LangOS et résume la page ».
