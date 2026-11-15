extends Node
## Agenda : événements, récurrence simple, rappels (Timer -> main.notify), persistance user://calendar.json, export/import .ics.
## Les dates sont en heure locale (« YYYY-MM-DD » + « HH:MM »), converties en secondes sans fuseau.
var m
var path := "user://calendar.json"
var events: Array = []      # {id, t, d, tm, rep, rem}
var fired: Array = []       # "id@date" déjà notifiés
var next_id := 1
const REPS := ["none", "daily", "weekly", "monthly"]

func _ready() -> void: load_data()

func start_timer() -> void:
	load_data()
	var t := Timer.new(); t.wait_time = 20.0; t.autostart = true; t.timeout.connect(check); add_child(t)

func load_data() -> void:
	if not FileAccess.file_exists(path): return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		events = d.get("events", []); fired = d.get("fired", []); next_id = int(d.get("next", 1))

func save() -> void:
	if fired.size() > 300: fired = fired.slice(fired.size() - 300)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"events": events, "fired": fired, "next": next_id}))

func add(title: String, d: String, tm := "09:00", rep := "none", rem := -1) -> Dictionary:
	var e := {"id": next_id, "t": title.strip_edges(), "d": d, "tm": tm, "rep": rep, "rem": rem}
	next_id += 1; events.append(e); save(); return e

func remove(id: int) -> void:
	events = events.filter(func(e): return int(e["id"]) != id); save()

static func day_num(ds: String) -> int: return int(Time.get_unix_time_from_datetime_string(ds + "T00:00:00") / 86400)
static func ds_of(num: int) -> String: return Time.get_date_string_from_unix_time(num * 86400)
static func now_unix() -> int: return int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system()))

func occurs(e: Dictionary, ds: String) -> bool:
	var a := day_num(e["d"]); var b := day_num(ds)
	if b < a: return false
	match e.get("rep", "none"):
		"daily": return true
		"weekly": return (b - a) % 7 == 0
		"monthly": return ds.substr(8, 2) == String(e["d"]).substr(8, 2)
	return b == a

func events_on(ds: String) -> Array:
	var out := events.filter(func(e): return occurs(e, ds))
	out.sort_custom(func(x, y): return x["tm"] < y["tm"])
	return out

## Rappels dus à l'instant `now` (secondes locales) : renvoie [{e, date}] et les marque comme notifiés.
func due(now: int) -> Array:
	var out := []
	var today := int(now / 86400)
	for e in events:
		if int(e.get("rem", -1)) < 0: continue
		for dn in [today, today + 1]:
			var ds := ds_of(dn)
			if not occurs(e, ds): continue
			var st := int(Time.get_unix_time_from_datetime_string("%sT%s:00" % [ds, e["tm"]]))
			var k := "%d@%s" % [e["id"], ds]
			if st - int(e["rem"]) * 60 <= now and now <= st + 600 and not fired.has(k):
				fired.append(k); out.append({"e": e, "date": ds})
	if not out.is_empty(): save()
	return out

func check() -> void:
	for x in due(now_unix()):
		if m: m.notify("Agenda : " + x["e"]["t"], "%s à %s" % [x["date"], x["e"]["tm"]])

# ---- ICS
func to_ics() -> String:
	var L := ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//LangOS//Agenda//FR"]
	for e in events:
		L += ["BEGIN:VEVENT", "UID:%d@langos" % e["id"], "DTSTART:%sT%s00" % [String(e["d"]).replace("-", ""), String(e["tm"]).replace(":", "")], "SUMMARY:" + _esc(e["t"])]
		if e["rep"] != "none": L.append("RRULE:FREQ=" + String(e["rep"]).to_upper())
		if int(e.get("rem", -1)) >= 0: L += ["BEGIN:VALARM", "ACTION:DISPLAY", "TRIGGER:-PT%dM" % e["rem"], "END:VALARM"]
		L.append("END:VEVENT")
	L.append("END:VCALENDAR")
	return "\r\n".join(L) + "\r\n"

static func _esc(s: String) -> String: return s.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", "\\n")
static func _unesc(s: String) -> String: return s.replace("\\n", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")

## Importe des VEVENT (DTSTART, SUMMARY, RRULE FREQ, VALARM TRIGGER) ; renvoie le nombre ajouté.
func from_ics(s: String) -> int:
	var n := 0
	var cur: Dictionary = {}
	for raw in s.replace("\r\n ", "").replace("\r", "").split("\n"):
		var l := raw.strip_edges()
		if l == "BEGIN:VEVENT": cur = {"t": "", "d": "", "tm": "09:00", "rep": "none", "rem": -1}
		elif l == "END:VEVENT":
			if not cur.is_empty() and cur["d"] != "": add(cur["t"] if cur["t"] != "" else "(sans titre)", cur["d"], cur["tm"], cur["rep"], cur["rem"]); n += 1
			cur = {}
		elif cur.is_empty(): continue
		elif l.begins_with("DTSTART"):
			var v := l.get_slice(":", 1)
			if v.length() >= 8 and v.substr(0, 8).is_valid_int():
				cur["d"] = "%s-%s-%s" % [v.substr(0, 4), v.substr(4, 2), v.substr(6, 2)]
				if v.length() >= 13 and v[8] == "T": cur["tm"] = "%s:%s" % [v.substr(9, 2), v.substr(11, 2)]
		elif l.begins_with("SUMMARY"): cur["t"] = _unesc(l.substr(l.find(":") + 1))
		elif l.begins_with("RRULE"):
			for part in l.get_slice(":", 1).split(";"):
				if part.begins_with("FREQ="):
					var fq := part.substr(5).to_lower()
					cur["rep"] = fq if fq in ["daily", "weekly", "monthly"] else "none"
		elif l.begins_with("TRIGGER"):
			var v := l.get_slice(":", 1)
			if v.begins_with("-PT") and v.ends_with("M") and v.substr(3, v.length() - 4).is_valid_int(): cur["rem"] = int(v.substr(3, v.length() - 4))
			elif v.begins_with("-PT") and v.ends_with("H") and v.substr(3, v.length() - 4).is_valid_int(): cur["rem"] = int(v.substr(3, v.length() - 4)) * 60
	return n

## Ajoute un événement à la liste « Tâches » (user://todo.json).
func to_todo(e: Dictionary) -> bool:
	var p := "user://todo.json"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else {"Tâches": [], "Courses": []}
	if not d is Dictionary or d.is_empty(): d = {"Tâches": [], "Courses": []}
	if not d.has("Tâches"): d["Tâches"] = []
	d["Tâches"].append({"t": "%s (%s %s)" % [e["t"], e["d"], e["tm"]], "d": false})
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(d)); return true
