extends SceneTree
## Test d'interface : aucune fenêtre ne doit dépasser du bureau, même sur un petit écran (téléphone, zoom élevé).
## Lancer (sans fenêtre) : flatpak run org.godotengine.Godot --headless --path . --script res://tests/ui_test.gd
## Sortie « UI-TEST OK » ou la liste des fenêtres qui dépassent.

const SKIP := ["hika", "chromium", "update"]    # hika/chromium chargent des moteurs lourds ; update interroge le réseau

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
			m._close_win(id)
		vp.queue_free()
		await create_timer(0.3).timeout
	print("UI-TEST %s : %d vérifications, %d problème(s)" % ["OK" if fails.is_empty() else "ECHEC", checks, fails.size()])
	for f in fails: print("  ✗ ", f)
	quit(0 if fails.is_empty() else 1)
