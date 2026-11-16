class_name Commands extends RefCounted
## Commandes texte (/home, /sethome, /spawn, /aide). Parsing séparé de l'interface :
## execute(texte) -> message, réutilisable par un futur chat.

const HELP := "Commandes : /home  /sethome  /spawn  /chat on|off  /hd on|off  /distant on|off  /fin on|off  /vue auto on|off  /tordu 0-30  /pierres on|off  /contour on|off  /zombies on|off  /aide"

var host  # nœud principal (main.gd) : player, world, _update_cut, _update_camera
var spawn_pos := Vector3.ZERO
var home := Vector3.ZERO
var on_teleport := Callable()  # (from: Vector3, to: Vector3) effet visuel facultatif

func _init(h = null, spawn := Vector3.ZERO) -> void:
	host = h
	spawn_pos = spawn
	home = spawn

func execute(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("/"):
		t = t.substr(1)
	var parts := t.split(" ", false)
	if parts.is_empty():
		return "Commande vide.  /aide pour la liste"
	match parts[0].to_lower():
		"home", "base":
			teleport(home)
			return "Retour à la base (%d, %d, %d)" % [floori(home.x), floori(home.y), floori(home.z)]
		"sethome":
			var err := _ground_error()
			if err != "":
				return err
			var p: Vector3 = host.player.pos
			home = Vector3(floorf(p.x) + 0.5, floorf(p.y + 0.05), floorf(p.z) + 0.5)
			return "Base définie ici (%d, %d, %d)" % [floori(home.x), floori(home.y), floori(home.z)]
		"spawn":
			if host.player.combat_t > 0.0:
				return "Impossible en combat"
			teleport(spawn_pos)
			return "Retour à la salle de spawn"
		"vue":
			var von: bool = not (parts.size() > 2 and parts[2].to_lower() == "off")
			host.view.auto_fps = von
			return "Vue automatique (FPS dans les passages étroits) " + ("activée" if von else "désactivée")
		"zombies":
			var zon: bool = not (parts.size() > 1 and parts[1].to_lower() == "off")
			host.zombies_off = not zon
			if not zon:
				for zz in host.zombies:
					(zz as Node).queue_free()
				host.zombies.clear()
			return "Zombies " + ("activés" if zon else "désactivés (supprimés)")
		"contour":
			var con: bool = not (parts.size() > 1 and parts[1].to_lower() == "off")
			VoxelBody.outline_on = con
			for o in host.get_tree().get_nodes_in_group("body_outline"):
				(o as Node3D).visible = con
			return "Contour dessin animé " + ("activé" if con else "désactivé")
		"pierres":
			var pon: bool = not (parts.size() > 1 and parts[1].to_lower() == "off")
			host._set_param("stone_on", 1.0 if pon else 0.0)
			return "Calepinage de pierres " + ("activé" if pon else "désactivé")
		"tordu":
			var tv := (float(parts[1]) / 100.0) if parts.size() > 1 and parts[1].is_valid_float() else 0.12
			DMSettings.tordu = clampf(tv, 0.0, 0.3)
			DMSettings.save_cfg()
			if host.view.mode != ViewCtl.CUT:
				host._set_param("jitter", DMSettings.tordu)
			return "Déformation des blocs : %d (0 = droits, 12 = défaut, 30 = très crochu)" % roundi(DMSettings.tordu * 100.0)
		"fin":
			var fon: bool = not (parts.size() > 1 and parts[1].to_lower() == "off")
			host.set_fine(fon)
			return "Mode fin " + ("activé" if fon else "désactivé") + "  (F4)"
		"distant":
			var on2: bool = not (parts.size() > 1 and parts[1].to_lower() == "off")
			var vp: Viewport = host.get_viewport()
			vp.msaa_3d = Viewport.MSAA_DISABLED if on2 else Viewport.MSAA_4X
			return "Mode jeu à distance " + ("activé : image légère (pas d'anticrénelage)" if on2 else "désactivé") + "  (/distant on|off)"
		"hd":
			DMSettings.hd = not (parts.size() > 1 and parts[1].to_lower() == "off")
			DMSettings.save_cfg()
			DMSettings.apply_video()
			return "Haute résolution " + ("activée" if DMSettings.hd else "coupée (gros pixels)") + "  (/hd on|off)"
		"chat":
			DMSettings.chat_bots = parts.size() > 1 and parts[1].to_lower() == "on"
			DMSettings.save_cfg()
			return "Messages des bots " + ("affichés" if DMSettings.chat_bots else "masqués") + "  (/chat on|off)"
		"aide", "help", "?":
			return HELP
	return "Commande inconnue : /%s  (/aide)" % parts[0]

## "" si le joueur est sur un sol sûr, sinon le motif du refus.
func _ground_error() -> String:
	var w: World = host.world
	var p: Vector3 = host.player.pos
	var feet := Vector3i(floori(p.x), floori(p.y + 0.05), floori(p.z))
	for d in [Vector3i.ZERO, Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
		if w.get_v(feet + d) == World.LAVA:
			return "Impossible : trop près de la lave"
	if not host.player.on_ground or not w.is_solid(w.get_v(feet - Vector3i(0, 1, 0))):
		return "Impossible : il faut un sol solide sous les pieds"
	return ""

func teleport(p: Vector3) -> void:
	var from: Vector3 = host.player.pos
	host.player.pos = p
	host.player.vel = Vector3.ZERO
	host.player.set_lane_axis(host.player.lane_axis)
	host.player.position = host.player.pos
	host._update_cut()
	host._update_camera(0.0, true)
	if on_teleport.is_valid():
		on_teleport.call(from, host.player.pos)

func to_dict() -> Dictionary:
	return {"home": [home.x, home.y, home.z]}

func from_dict(d: Dictionary) -> void:
	var h: Array = d.get("home", [])
	if h.size() == 3:
		home = Vector3(h[0], h[1], h[2])
