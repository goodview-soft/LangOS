extends SceneTree
## Test d'interface : aucune fenêtre ne doit dépasser du bureau (3 tailles), aucun texte ne doit être coupé ou sortir de la fenêtre,
## et le texte doit rester lisible (contraste) dans les deux thèmes.
## Lancer (sans fenêtre) : flatpak run org.godotengine.Godot --headless --path . --script res://tests/ui_test.gd
## Sortie « UI-TEST OK » ou la liste des problèmes.

const SKIP := ["hika", "deepminer", "chromium", "update"]    # hika/chromium chargent des moteurs lourds ; update interroge le réseau
const UI = preload("res://apps/ui.gd")

## Texte d'un Label visiblement coupé : trop étroit pour son contenu alors qu'il n'est ni à la ligne ni rogné volontairement.
func _clipped(c: Control, win: Rect2) -> String:
	var r := c.get_global_rect()
	if r.size.x < 1.0 or r.size.y < 1.0: return ""
	if r.position.x < win.position.x - 2.0 or r.end.x > win.end.x + 2.0: return "hors de la fenêtre « %s »" % (c.text.left(24) if c is Label else c.name)
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
			if c.is_visible_in_tree():
				if c is Label or c is Button:
					var why := _clipped(c, win)
					if why != "" and not (c is Button): out.append("%s (%s)" % [why, str(c.get_path()).get_slice("/", 6) + "/" + c.name])
				# Seul un défilement horizontal réellement actif excuse un contenu plus large ; clip_contents ou défilement vertical seul ne masquent rien.
				if c is ScrollContainer and (c as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: continue
				_walk(c, win, out)
		else:
			_walk(ch, win, out)

func get_nodes_in_group_of(m: Node, g: String) -> Array: return m.get_tree().get_nodes_in_group(g)

func _init() -> void:
	var fails: Array = []
	var checks := 0
	for size in [Vector2i(700, 1200), Vector2i(1280, 720), Vector2i(1000, 600), Vector2i(360, 780), Vector2i(300, 640)]:
		var vp := SubViewport.new(); vp.size = size; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
		var m = load("res://main.tscn").instantiate(); vp.add_child(m); m.set_cfg["installed"] = m.APPS.keys()
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
		# Clavier visuel : doit tenir dans la largeur du bureau et ≤ 45 % de sa hauteur
		m.kb.visible = true; m._fit_kb(); await create_timer(0.2).timeout
		checks += 2
		var kmn: Vector2 = m.kb.get_combined_minimum_size()
		if kmn.x > m.size.x + 1.0: fails.append("clavier à %s : trop large (minimum %.0f > %.0f)" % [str(size), kmn.x, m.size.x])
		if size.x < 760 and kmn.y > m.desk.size.y * 0.45 + 2.0: fails.append("clavier à %s : trop haut (%.0f > 45 %% de %.0f)" % [str(size), kmn.y, m.desk.size.y])
		m.kb.visible = false
		# Recoloration à chaud : les panneaux stylés à la construction suivent le thème de fenêtres déjà ouvertes
		if size.x == 700:
			m.set_cfg["light"] = false; m._restyle()
			for id in ["music", "messenger", "notes"]: m._open_app(id)
			await create_timer(0.5).timeout
			var before := {}
			for n in get_nodes_in_group_of(m, "themed"):
				if n is PanelContainer and n.has_theme_stylebox_override("panel") and n.is_visible_in_tree() and n.get_theme_stylebox("panel") is StyleBoxFlat:
					before[n] = (n.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
			checks += 1
			if before.size() < 3: fails.append("recoloration : seulement %d panneaux thématiques trouvés" % before.size())
			m._set_light(true); m.set_cfg["radius"] = 3; m._restyle()
			var changed := 0
			for n in before:
				if is_instance_valid(n) and (n.get_theme_stylebox("panel") as StyleBoxFlat).bg_color != before[n]: changed += 1
			checks += 1
			if changed < before.size() * 0.8: fails.append("recoloration : %d/%d panneaux ont changé de couleur" % [changed, before.size()])
			m.set_cfg["radius"] = 12; m.set_cfg["light"] = false; m._restyle()
			for id in ["music", "messenger", "notes"]: m._close_win(id)
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
	# aucun bouton de barre ne doit garder un texte symbolique (icônes Lucide à la place)
	var sym := RegEx.create_from_string("(?:\\.text = |_btn\\(|button\\()\"[\\s]*[☰◀▶⋮✓⟳＋✕×☆★⇄‹›⟲⟳📎📳💬📂][^\"]{0,2}\"")
	for f in DirAccess.get_files_at("res://apps"):
		if not f.ends_with(".gd") or f == "soundlink.gd": continue
		var src := FileAccess.get_file_as_string("res://apps/" + f)
		for ln in src.split("\n"):
			if ln.strip_edges().begins_with("#"): continue
			checks += 1
			var mm := sym.search(ln)
			if mm != null and not ("label" in ln.to_lower() and "Label.new" in ln): fails.append("texte symbolique sur un bouton (%s) : %s" % [f, ln.strip_edges().left(70)])
	print("UI-TEST %s : %d vérifications, %d problème(s)" % ["OK" if fails.is_empty() else "ECHEC", checks, fails.size()])
	for f in fails: print("  ✗ ", f)
	quit(0 if fails.is_empty() else 1)
