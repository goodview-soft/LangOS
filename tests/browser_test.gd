extends SceneTree
## Tests logiques du navigateur (sans moteur). Sortie : « BROWSER-TEST OK ».
const BrowserCore := preload("res://apps/browser_core.gd")
var fails: Array = []
var checks := 0
func check(n: String, c: bool, info := "") -> void:
	checks += 1
	if not c: fails.append("%s %s" % [n, info])

func _init() -> void:
	var d := "user://bt_test"
	var b := BrowserCore.new(d)
	# onglets
	b.open_tab(); b.open_tab("https://a.fr"); b.open_tab("https://b.fr")
	check("3 onglets", b.tabs.size() == 3 and b.active == 2)
	b.move_tab(2, 0); check("réordonner", b.tabs[0]["url"] == "https://b.fr" and b.active == 0)
	b.close_tab(0); check("fermer", b.tabs.size() == 2 and b.active == 0)
	b.close_tab(0); b.close_tab(0); check("jamais vide", b.tabs.size() == 1)
	# historique / privé
	b.navigated(0, "https://x.org/", "X")
	check("historique", b.history.size() == 1 and b.search_history("x").size() == 1)
	var p := b.open_tab("https://secret.org", true)
	b.navigated(p, "https://secret.org/page", "S")
	check("privé sans historique", b.history.size() == 1)
	# favoris
	b.add_folder("Dev"); b.add_bookmark("Godot", "https://godotengine.org", [0]); b.add_bookmark("Racine", "https://r.fr")
	check("favoris", b.count_bookmarks() == 2 and b.find_bookmark("https://godotengine.org"))
	b.remove_item(0, [0]); check("suppr favori", b.count_bookmarks() == 1)
	# adblock
	check("ad match", BrowserCore.is_ad_url("https://ad.doubleclick.net/x?y=1") and BrowserCore.is_ad_url("http://doubleclick.net"))
	check("ad non-match", not BrowserCore.is_ad_url("https://notdoubleclick.net/") and not BrowserCore.is_ad_url("https://example.com/doubleclick.net"))
	check("ad chemin", BrowserCore.is_ad_url("https://yandex.ru/ads/x") and not BrowserCore.is_ad_url("https://yandex.ru/search"))
	check("liste >= 150", BrowserCore.AD_DOMAINS.size() >= 150)
	b.should_block("https://criteo.com/a"); b.adblock = false; b.should_block("https://criteo.com/a")
	check("compteur", b.blocked == 1)
	b.adblock = true
	# téléchargements
	var id := b.dl_start("https://f.fr/a.zip", "/tmp/a.zip", 200)
	check("dl 50%", not b.dl_update(id, 100) and BrowserCore.dl_percent(b.downloads[0]) == 50)
	check("dl fin", b.dl_update(id, 200, -1, true) and b.downloads[0]["state"] == "done" and not b.dl_update(id, 200, -1, true))
	# coffre
	var ents := [{"site": "a.fr", "user": "moi", "pw": "s3cr3t é"}]
	var v := BrowserCore.vault_encrypt(ents, "maitre")
	check("coffre aller-retour", BrowserCore.vault_decrypt(v, "maitre") == ents)
	check("coffre mauvais mdp", BrowserCore.vault_decrypt(v, "faux") == null)
	check("coffre pas en clair", not JSON.stringify(v).contains("s3cr3t"))
	# persistance
	b.add_bookmark("Persist", "https://p.fr"); b.desktop_mode = false
	b.vault_save(ents, "maitre"); b.save()
	check("privé non sauvé", not FileAccess.get_file_as_string(d + "/state.json").contains("secret.org") and not FileAccess.get_file_as_string(d + "/history.json").contains("secret"))
	check("vault disque chiffré", not FileAccess.get_file_as_string(d + "/vault.json").contains("s3cr3t"))
	var c := BrowserCore.new(d); c.load_all()
	check("restauration", c.tabs.size() == 1 and c.tabs[0]["url"] == "https://x.org/" and not c.desktop_mode and c.find_bookmark("https://p.fr") and c.history.size() == 1)
	check("vault load", c.vault_load("maitre") == ents and c.vault_load("x") == null)
	# privé seul : rien ne s'écrit sur les onglets
	var e := BrowserCore.new("user://bt_test2"); e.tabs.clear(); e.open_tab("https://p.org", true); e.navigated(0, "https://p.org/z", "z"); e.save()
	check("privé seul", e.history.is_empty() and not FileAccess.get_file_as_string("user://bt_test2/state.json").contains("p.org"))
	for dd in [d, "user://bt_test2"]:
		for f in DirAccess.get_files_at(dd): DirAccess.remove_absolute(dd + "/" + f)
		DirAccess.remove_absolute(dd)
	if fails.is_empty(): print("BROWSER-TEST OK (%d vérifications)" % checks); quit(0)
	else: print("BROWSER-TEST ÉCHEC :\n" + "\n".join(fails)); quit(1)
