class_name Lyrics
extends Node
## Recherche automatique de paroles synchronisées (LRC) sur LRCLIB + parsing.

const API := "https://lrclib.net/api/"
const HEADERS := ["User-Agent: LangOS (Godot app)"]


## Renvoie le texte LRC synchronisé, ou "" si rien trouvé.
func fetch(artist: String, title: String, duration: float) -> String:
	var t := clean_title(title)
	if artist != "":
		var q := "get?artist_name=%s&track_name=%s" % [artist.uri_encode(), t.uri_encode()]
		if duration > 0:
			q += "&duration=%d" % int(duration)
		var d = await _get_json(q)
		if d is Dictionary and str(d.get("syncedLyrics", "")) not in ["", "<null>"]:
			return d["syncedLyrics"]
	var best := ""
	var best_diff := INF
	for query in [("%s %s" % [artist, t]).strip_edges(), t]:
		var res = await _get_json("search?q=" + query.uri_encode())
		if res is Array:
			for r in res:
				var s = r.get("syncedLyrics")
				if s == null or str(s) == "":
					continue
				var diff := absf(float(r.get("duration", 0)) - duration) if duration > 0 else 0.0
				if diff < best_diff:
					best_diff = diff
					best = s
		if best != "" and best_diff < 8:
			break
	return best


func _get_json(q: String):
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15
	if http.request(API + q, HEADERS) != OK:
		http.queue_free()
		return null
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return null
	return JSON.parse_string(r[3].get_string_from_utf8())


## Nettoie un titre YouTube : "(Official Video)", "[Lyrics]", "ft. X", etc.
static func clean_title(s: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)\\s*[\\(\\[][^\\)\\]]*(official|video|vid[ée]o|lyric|audio|clip|hd|4k|visuali[sz]er|paroles|remaster|music)[^\\)\\]]*[\\)\\]]")
	s = re.sub(s, "", true)
	re.compile("(?i)\\s+(ft\\.?|feat\\.?|featuring)\\s.*$")
	s = re.sub(s, "")
	s = s.split("|")[0]
	re.compile("\\s*\\[[^\\]]*\\]")
	s = re.sub(s, "", true)
	return s.strip_edges()


## Devine [artiste, titre] depuis les métadonnées yt-dlp.
static func guess(title: String, artist: String, track: String, uploader: String) -> Array:
	if artist not in ["", "NA"] and track not in ["", "NA"]:
		return [artist.split(",")[0].strip_edges(), track]
	for sep in [" - ", " – ", " — "]:
		if sep in title:
			var p := title.split(sep, true, 1)
			return [clean_title(p[0]), clean_title(p[1])]
	var t := clean_title(title)
	var up := uploader.replace(" - Topic", "").replace("VEVO", "").strip_edges()
	return [up, t]


## Parse un LRC → Array de [temps_sec, texte], trié.
static func parse(lrc: String) -> Array:
	var out := []
	var offset := 0.0
	var re := RegEx.new()
	re.compile("\\[(\\d+):(\\d+(?:[.:]\\d+)?)\\]")
	for line in lrc.split("\n"):
		line = line.strip_edges()
		if line.begins_with("[offset:"):
			offset = line.trim_prefix("[offset:").trim_suffix("]").to_float() / 1000.0
			continue
		var tags := re.search_all(line)
		if tags.is_empty():
			continue
		var text := line.substr(tags[-1].get_end()).strip_edges()
		for m in tags:
			var t := m.get_string(1).to_float() * 60.0 + m.get_string(2).replace(":", ".").to_float()
			out.append([t - offset, text])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out
