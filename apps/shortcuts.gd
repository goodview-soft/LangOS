extends Node
## Raccourcis clavier personnalisables + remappage de manette. Réglages dans settings.cfg (set_cfg["keys"], set_cfg["padmap"]).
## Actions : id -> [libellé, touche par défaut, verrouillée]. Les verrouillées sont gérées en dur par main._input (non modifiables, mais comptées dans les conflits).
var m
var capture := Callable()           # si valide : reçoit la prochaine combinaison (String) au lieu de la déclencher
const FIXED := {
	"search": ["Recherche globale", "Ctrl+Space", true],
	"vd_prev": ["Bureau précédent", "Ctrl+Alt+Left", true],
	"vd_next": ["Bureau suivant", "Ctrl+Alt+Right", true],
	"chat": ["Chat IA (hors saisie)", "Minus", true],
}
const BASE := {
	"clip": ["Presse-papiers flottant", "Ctrl+Shift+V", false],
	"vd:0": ["Bureau 1", "Ctrl+Alt+1", false], "vd:1": ["Bureau 2", "Ctrl+Alt+2", false],
	"vd:2": ["Bureau 3", "Ctrl+Alt+3", false], "vd:3": ["Bureau 4", "Ctrl+Alt+4", false],
	"snap:l": ["Ancrer à gauche", "Ctrl+Alt+Shift+Left", false], "snap:r": ["Ancrer à droite", "Ctrl+Alt+Shift+Right", false],
	"snap:t": ["Ancrer en haut", "Ctrl+Alt+Shift+Up", false], "snap:b": ["Ancrer en bas", "Ctrl+Alt+Shift+Down", false],
	"overview": ["Vue d'ensemble des fenêtres", "Ctrl+Alt+Tab", false],
	"theme": ["Thème clair / sombre", "Ctrl+Alt+L", false],
}
const APP_KEYS := {"notepad": "Ctrl+Alt+N", "terminal": "Ctrl+Alt+T", "files": "Ctrl+Alt+F", "settings": "Ctrl+Alt+S", "chromium": "Ctrl+Alt+B"}

## Table complète (ordre d'affichage) : id -> [libellé, défaut, verrouillée].
func actions() -> Dictionary:
	var d := {}
	for k in FIXED: d[k] = FIXED[k]
	for k in BASE: d[k] = BASE[k]
	if m != null:
		for id in m.APPS:
			if not m.FOLDERS.has(id) and id != "android_apps" and not m.HIDDEN.has(id): d["app:" + id] = ["Ouvrir " + str(m.APPS[id][0]), APP_KEYS.get(id, ""), false]
		if m.prof != null:
			for p in m.prof.all(): d["prof:" + str(p["name"])] = ["Profil " + str(p["name"]), "", false]
	return d

static func event_str(ev: InputEventKey) -> String:
	var k := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	if k in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META, KEY_NONE]: return ""
	var s := ""
	if ev.ctrl_pressed: s += "Ctrl+"
	if ev.alt_pressed: s += "Alt+"
	if ev.shift_pressed: s += "Shift+"
	if ev.meta_pressed: s += "Meta+"
	return s + OS.get_keycode_string(k)

## Une combinaison valide a Ctrl, Alt ou Méta (ou est une touche F1..F12) : jamais une simple lettre.
static func valid(s: String) -> bool:
	return s.begins_with("Ctrl+") or s.begins_with("Alt+") or s.begins_with("Meta+") or s.begins_with("Shift+F") or (s.begins_with("F") and s.length() <= 3)

func binding(a: String) -> String:
	var keys: Dictionary = m.set_cfg.get("keys", {})
	if keys.has(a): return str(keys[a])
	var d: Dictionary = actions()
	return str(d[a][1]) if d.has(a) else ""

## Action (non verrouillée) liée à cette combinaison, ou "".
func find_action(s: String) -> String:
	if s == "": return ""
	var d := actions()
	for a in d: if not d[a][2] and binding(a) == s: return a
	return ""

## Action qui utilise déjà cette combinaison (verrouillées comprises), hors « except ».
func conflict(s: String, except := "") -> String:
	if s == "": return ""
	var d := actions()
	for a in d: if a != except and binding(a) == s: return a
	return ""

## Assigne une touche. Renvoie "" si OK, sinon l'id de l'action en conflit (rien n'est modifié) ; « force » retire l'ancienne liaison.
func assign(a: String, s: String, force := false) -> String:
	var d := actions()
	if not d.has(a) or d[a][2]: return a
	if s != "":
		var c := conflict(s, a)
		if c != "":
			if not force or d[c][2]: return c
			m.set_cfg["keys"][c] = ""
	m.set_cfg["keys"][a] = s; m._save_settings(); return ""

func reset(a: String) -> void:
	m.set_cfg["keys"].erase(a); m._save_settings()

## Exécute une action ; renvoie false si elle est inconnue ou impossible.
func run(a: String) -> bool:
	if a.begins_with("vd:"):
		var n := int(a.get_slice(":", 1))
		if n < m.n_vd: m._goto_vd(n); return true
	elif a.begins_with("snap:"):
		if m.active != "" and m.wins.has(m.active): m._snap(m.active, a.get_slice(":", 1)); return true
	elif a.begins_with("app:"):
		var id := a.substr(4)
		if m.APPS.has(id): m._open_app(id); return true
	elif a.begins_with("prof:"):
		var i: int = m.prof.find(a.substr(5))
		if i >= 0: m.prof.activate(i); return true
	else:
		match a:
			"clip": m.clip.toggle(); return true
			"search": m.srch.toggle(); return true
			"overview": m.overview.toggle(); return true
			"theme": m._set_light(not bool(m.set_cfg.get("light", false))); return true
			"vd_next": m._goto_vd(posmod(m.cur_vd + 1, m.n_vd)); return true
			"vd_prev": m._goto_vd(posmod(m.cur_vd - 1, m.n_vd)); return true
			"chat": if m.chat_ov: m.chat_ov.toggle(); return true
	return false

## Appelé par main._input en premier ; renvoie true si l'événement est consommé.
func handle(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var s := event_str(ev)
		if s == "": return false
		if capture.is_valid():
			var cb := capture; capture = Callable(); cb.call("" if s == "Escape" else s); return true
		var a := find_action(s)
		return a != "" and run(a)
	if ev is InputEventJoypadButton and ev.pressed:
		var pm: Dictionary = m.set_cfg.get("padmap", {})
		return pm.has(str(ev.button_index)) and run(str(pm[str(ev.button_index)]))
	return false
