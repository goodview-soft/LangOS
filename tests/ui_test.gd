extends SceneTree
## Test d'interface : aucune fenêtre ne doit dépasser du bureau (3 tailles), aucun texte ne doit être coupé ou sortir de la fenêtre,
## et le texte doit rester lisible (contraste) dans les deux thèmes.
## Lancer (sans fenêtre) : flatpak run org.godotengine.Godot --headless --path . --script res://tests/ui_test.gd
## Sortie « UI-TEST OK » ou la liste des problèmes.

const SKIP := ["hika", "chromium", "update"]    # hika/chromium chargent des moteurs lourds ; update interroge le réseau
const UI = preload("res://apps/ui.gd")

## Texte d'un Label visiblement coupé : trop étroit pour son contenu alors qu'il n'est ni à la ligne ni rogné volontairement.
func _clipped(c: Control, win: Rect2) -> String:
	var r := c.get_global_rect()
	if r.size.x < 1.0 or r.size.y < 1.0: return ""
	if r.position.x < win.position.x - 2.0 or r.end.x > win.end.x + 2.0: return "hors de la fenêtre"
	if c is Label:
		var l: Label = c
		if l.text == "" or l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING: return ""
		var f := l.get_theme_font("font"); var sz := l.get_theme_font_size("font_size")
		var w := f.get_string_size(l.text.get_slice("\n", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if w > r.size.x + 2.0 and l.get_combined_minimum_size().x > r.size.x + 2.0: return "texte coupé « %s »" % l.text.left(30)
	return ""

func _walk(n: Node, win: Rect2, out: Array) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c: Control = ch
			if c.is_visible_in_tree() and not (c is ScrollContainer) and not c.clip_contents:
				if c is Label or c is Button:
					var why := _clipped(c, win)
					if why != "" and not (c is Button): out.append("%s (%s)" % [why, str(c.get_path()).get_slice("/", 6) + "/" + c.name])
				_walk(c, win, out)
		else:
			_walk(ch, win, out)

func _init() -> void:
	var fails: Array = []
	var checks := 0
	for size in [Vector2i(700, 1200), Vector2i(1280, 720), Vector2i(1000, 600)]:
		var vp := SubViewport.new(); vp.size = size; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
		var m = load("res://main.tscn").instantiate(); vp.add_child(m)
		await create_timer(0.8).timeout
		for id in m.APPS.keys():
			if id in SKIP or m.FOLDERS.has(id): continue
			m._open_app(id)
			await create_timer(0.25).timeout
			if not m.wins.has(id): continue
			var w: PanelContainer = m.wins[id]["win"]
			await create_timer(0.1).timeout
			var ds: Vector2 = m.desk.size
			var mn := w.get_combined_minimum_size()
			checks += 2
			if w.position.x + w.size.x > ds.x + 1.0 or w.position.x < -1.0: fails.append("%s à %s : fenêtre hors du bureau (x=%.0f largeur=%.0f bureau=%.0f)" % [id, str(size), w.position.x, w.size.x, ds.x])
			if mn.x > ds.x + 1.0: fails.append("%s à %s : contenu trop large (minimum %.0f > bureau %.0f)" % [id, str(size), mn.x, ds.x])
			var cl: Array = []
			_walk(w, w.get_global_rect(), cl); checks += 1
			for s in cl.slice(0, 3): fails.append("%s à %s : %s" % [id, str(size), s])
			m._close_win(id)
		# Contraste : texte / fond des cartes et des champs, dans les deux thèmes
		for light in [false, true]:
			m.set_cfg["light"] = light; m._restyle()
			for pair in [["text", "win"], ["text", "card"], ["text", "field"], ["muted", "win"], ["muted", "card"], ["ok", "card"], ["warn", "card"], ["err", "card"], ["text", "popup"]]:
				checks += 1
				var r: float = UI.contrast(m._p(pair[0]), m._p(pair[1]))
				if r < (3.0 if pair[0] in ["ok", "warn", "err"] else 4.5): fails.append("contraste %s/%s thème %s : %.1f" % [pair[0], pair[1], "clair" if light else "sombre", r])
			checks += 1
			var bubs: float = UI.contrast(Color.WHITE, m._p("bub_me"))
			if bubs < 4.5: fails.append("contraste bulle « moi » %s : %.1f" % ["clair" if light else "sombre", bubs])
			if UI.contrast(m._p("text"), m._p("bub_you")) < 4.5: fails.append("contraste bulle « eux » thème %s" % ("clair" if light else "sombre"))
		m.set_cfg["light"] = false
		vp.queue_free()
		await create_timer(0.3).timeout
	print("UI-TEST %s : %d vérifications, %d problème(s)" % ["OK" if fails.is_empty() else "ECHEC", checks, fails.size()])
	for f in fails: print("  ✗ ", f)
	quit(0 if fails.is_empty() else 1)
