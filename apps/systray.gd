extends Control
## Zone d'état de la barre des tâches : réseau (Wi-Fi / mobile / filaire / aucun) et batterie, comme sur un PC.
## Android : plugin natif « LangLauncher ».systemStatus() ; Linux : /sys/class/power_supply et /sys/class/net.

const UI = preload("res://apps/ui.gd")
var OK := Color("e5e9f0")
var DIM := Color(1, 1, 1, 0.3)
var batt := -1            # % ou -1 si pas de batterie
var charging := false
var net := "none"         # wifi | cell | eth | none
var level := 3            # force du Wi-Fi 0..3

func _ready() -> void:
	custom_minimum_size = Vector2(120, UI.tp(32))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Timer.new(); t.wait_time = 5.0; t.autostart = true; t.timeout.connect(_poll); add_child(t)
	_poll()

func _poll() -> void:
	if OS.get_name() == "Android":
		if Engine.has_singleton("LangLauncher") and int(Engine.get_singleton("LangLauncher").nativeLevel()) >= 6:
			var d = JSON.parse_string(str(Engine.get_singleton("LangLauncher").systemStatus()))
			if d is Dictionary:
				batt = int(d.get("battery", -1)); charging = bool(d.get("charging", false)); net = str(d.get("net", "none")); level = int(d.get("level", 3))
	else:
		_poll_linux()
	queue_redraw()

func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p).strip_edges() if FileAccess.file_exists(p) else ""

func _poll_linux() -> void:
	batt = -1
	for d in DirAccess.get_directories_at("/sys/class/power_supply"):
		var b := "/sys/class/power_supply/" + d
		if _read(b + "/type") == "Battery" and _read(b + "/capacity") != "":
			batt = int(_read(b + "/capacity")); charging = _read(b + "/status") in ["Charging", "Full"]; break
	net = "none"
	for d in DirAccess.get_directories_at("/sys/class/net"):
		if d == "lo" or _read("/sys/class/net/" + d + "/operstate") != "up": continue
		if DirAccess.dir_exists_absolute("/sys/class/net/" + d + "/wireless"): net = "wifi"; level = 3; break
		if net == "none": net = "eth"
	if net == "none":   # état « unknown » (USB, pont…) : une adresse IPv4 locale suffit
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."): net = "eth"; break

func _draw() -> void:
	OK = UI.p("text"); DIM = Color(OK, 0.3)
	var h := size.y
	var x := 4.0
	_draw_net(Vector2(x + 12, h / 2.0))
	x += 30.0
	if batt >= 0:
		_draw_batt(Vector2(x, h / 2.0))

func _draw_net(c: Vector2) -> void:
	match net:
		"wifi":
			var base := c + Vector2(0, 8)
			for i in 3:
				draw_arc(base, 5.0 + i * 5.0, deg_to_rad(225), deg_to_rad(315), 12, OK if i < level or level >= 3 else DIM, 2.0)
			draw_circle(base, 2.0, OK)
		"cell":
			for i in 4:
				var bh := 4.0 + i * 3.5
				draw_rect(Rect2(c.x - 9 + i * 5, c.y + 8 - bh, 3.5, bh), OK if i < level + 1 else DIM)
		"eth":
			draw_rect(Rect2(c.x - 9, c.y - 6, 18, 12), OK, false, 2.0)
			draw_line(c + Vector2(-4, 6), c + Vector2(-4, 10), OK, 2.0); draw_line(c + Vector2(4, 6), c + Vector2(4, 10), OK, 2.0)
		_:
			var base := c + Vector2(0, 8)
			for i in 3: draw_arc(base, 5.0 + i * 5.0, deg_to_rad(225), deg_to_rad(315), 12, DIM, 2.0)
			draw_line(c + Vector2(-10, -8), c + Vector2(10, 10), UI.err(), 2.5)

func _draw_batt(p: Vector2) -> void:
	var w := 26.0
	var h := 13.0
	var col := UI.ok() if batt > 30 else (UI.warn() if batt > 15 else UI.err())
	draw_rect(Rect2(p.x, p.y - h / 2.0, w, h), OK, false, 1.6)
	draw_rect(Rect2(p.x + w + 1, p.y - 3.0, 2.5, 6.0), OK)
	draw_rect(Rect2(p.x + 2.2, p.y - h / 2.0 + 2.2, (w - 4.4) * clampf(batt / 100.0, 0.0, 1.0), h - 4.4), col)
	if charging:
		var b := PackedVector2Array([Vector2(p.x + 14, p.y - 5), Vector2(p.x + 9, p.y + 1), Vector2(p.x + 13, p.y + 1), Vector2(p.x + 11, p.y + 6), Vector2(p.x + 17, p.y - 1), Vector2(p.x + 13, p.y - 1)])
		draw_colored_polygon(b, Color(0.1, 0.1, 0.1, 0.85))
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(p.x + w + 8, p.y + 5), "%d%%" % batt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, OK)
