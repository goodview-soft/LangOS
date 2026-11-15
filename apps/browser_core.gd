extends RefCounted
## Logique du navigateur sans moteur : onglets, favoris (dossiers), historique, téléchargements,
## blocage de publicités, coffre de mots de passe chiffré. Rien ici n'appelle Chromium/WebView.
## Les onglets privés ne laissent aucune trace (ni historique, ni sauvegarde sur disque).

const HOME := "https://duckduckgo.com/"
const UA_DESKTOP := "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
const HIST_MAX := 1000

var dir := "user://browser"
var tabs: Array = []          # {id, url, title, private}
var active := 0
var next_id := 1
var bookmarks: Array = []     # {t:"f", name, items:[]} ou {t:"b", name, url}
var history: Array = []       # {url, title, time}
var downloads: Array = []     # {id, name, url, path, received, total, state: "run"|"done"|"fail"}
var desktop_mode := true
var adblock := true
var blocked := 0
var primary := true            # fenêtres secondaires : l'état des onglets n'est ni lu ni écrit

func _init(d := "user://browser") -> void: dir = d

# ------------------------------------------------------------ Onglets
func open_tab(url := HOME, priv := false, go_active := true) -> int:
	tabs.append({"id": next_id, "url": url, "title": "Nouvel onglet" if url == HOME else url, "private": priv}); next_id += 1
	if go_active: active = tabs.size() - 1
	return tabs.size() - 1

func close_tab(i: int) -> void:
	if i < 0 or i >= tabs.size(): return
	tabs.remove_at(i)
	if tabs.is_empty(): open_tab()
	elif active > i or active >= tabs.size(): active = maxi(0, mini(active - (1 if active > i else 0), tabs.size() - 1))

func move_tab(from: int, to: int) -> void:
	if from < 0 or from >= tabs.size() or to < 0 or to >= tabs.size() or from == to: return
	var cur: Dictionary = tabs[active]
	var t: Dictionary = tabs[from]; tabs.remove_at(from); tabs.insert(to, t)
	active = tabs.find(cur)

func current() -> Dictionary:
	if tabs.is_empty(): open_tab()
	return tabs[active]

## Appelé quand la page d'un onglet change : met à jour l'onglet et l'historique (sauf en privé).
func navigated(i: int, url: String, title := "") -> void:
	if i < 0 or i >= tabs.size(): return
	var t: Dictionary = tabs[i]
	t["url"] = url
	if title != "": t["title"] = title
	if not t["private"] and url.begins_with("http"): add_history(url, str(t["title"]))

# ------------------------------------------------------------ Historique
func add_history(url: String, title := "") -> void:
	if not history.is_empty() and history[0]["url"] == url:
		history[0]["title"] = title; return
	history.push_front({"url": url, "title": title, "time": Time.get_unix_time_from_system()})
	if history.size() > HIST_MAX: history.resize(HIST_MAX)

func search_history(q: String) -> Array:
	q = q.to_lower(); var r := []
	for h in history:
		if q == "" or str(h["url"]).to_lower().contains(q) or str(h["title"]).to_lower().contains(q): r.append(h)
	return r

# ------------------------------------------------------------ Favoris
## `path` = indices de dossiers depuis la racine ([] = racine).
func _items(path: Array) -> Array:
	var l := bookmarks
	for i in path:
		if i < 0 or i >= l.size() or l[i]["t"] != "f": return []
		l = l[i]["items"]
	return l

func add_folder(name: String, path := []) -> void:
	var l := _items(path) if not path.is_empty() else bookmarks
	l.append({"t": "f", "name": name, "items": []})

func add_bookmark(name: String, url: String, path := []) -> void:
	var l := _items(path) if not path.is_empty() else bookmarks
	l.append({"t": "b", "name": name, "url": url})

func remove_item(idx: int, path := []) -> void:
	var l := _items(path) if not path.is_empty() else bookmarks
	if idx >= 0 and idx < l.size(): l.remove_at(idx)

func find_bookmark(url: String, l = null) -> bool:
	if l == null: l = bookmarks
	for it in l:
		if it["t"] == "b" and it["url"] == url: return true
		if it["t"] == "f" and find_bookmark(url, it["items"]): return true
	return false

func count_bookmarks(l = null) -> int:
	if l == null: l = bookmarks
	var n := 0
	for it in l: n += 1 if it["t"] == "b" else count_bookmarks(it["items"])
	return n

# ------------------------------------------------------------ Téléchargements
func dl_start(url: String, path: String, total := 0) -> int:
	var d := {"id": next_id, "name": path.get_file(), "url": url, "path": path, "received": 0, "total": total, "state": "run"}
	next_id += 1; downloads.push_front(d); return int(d["id"])

## Retourne true quand ce passage termine le téléchargement.
func dl_update(id: int, received: int, total := -1, done := false, failed := false) -> bool:
	for d in downloads:
		if d["id"] != id: continue
		d["received"] = received
		if total >= 0: d["total"] = total
		if failed: d["state"] = "fail"; return false
		if done and d["state"] == "run": d["state"] = "done"; return true
	return false

static func dl_percent(d: Dictionary) -> int:
	if d["state"] == "done": return 100
	return int(100.0 * float(d["received"]) / float(d["total"])) if int(d["total"]) > 0 else 0

# ------------------------------------------------------------ Bloqueur de publicités
const AD_DOMAINS := ["doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com", "googletagmanager.com", "googletagservices.com", "adservice.google.com", "pagead2.googlesyndication.com", "adsystem.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "adform.net", "advertising.com", "criteo.com", "criteo.net", "outbrain.com", "taboola.com", "scorecardresearch.com", "quantserve.com", "moatads.com", "pubmatic.com", "rubiconproject.com", "openx.net", "casalemedia.com", "indexww.com", "contextweb.com", "smartadserver.com", "teads.tv", "media.net", "yieldmo.com", "sharethrough.com", "triplelift.com", "bidswitch.net", "3lift.com", "gumgum.com", "lijit.com", "sovrn.com", "spotxchange.com", "springserve.com", "tremorhub.com", "adcolony.com", "applovin.com", "unity3d.com/ads", "unityads.unity3d.com", "chartboost.com", "inmobi.com", "vungle.com", "ironsrc.com", "supersonicads.com", "mopub.com", "facebook.net", "connect.facebook.net", "graph.facebook.com/tr", "pixel.facebook.com", "analytics.twitter.com", "ads-twitter.com", "ads.twitter.com", "static.ads-twitter.com", "ads.linkedin.com", "px.ads.linkedin.com", "analytics.tiktok.com", "ads.tiktok.com", "ads.pinterest.com", "ads.yahoo.com", "analytics.yahoo.com", "advertising.yahoo.com", "adtech.com", "adtechus.com", "hotjar.com", "mouseflow.com", "crazyegg.com", "fullstory.com", "luckyorange.com", "inspectlet.com", "mixpanel.com", "segment.io", "segment.com", "amplitude.com", "heap.io", "heapanalytics.com", "newrelic.com", "nr-data.net", "bugsnag.com", "branch.io", "adjust.com", "appsflyer.com", "kochava.com", "singular.net", "tapad.com", "bluekai.com", "demdex.net", "omtrdc.net", "everesttech.net", "krxd.net", "exelator.com", "agkn.com", "rlcdn.com", "liveramp.com", "bounceexchange.com", "mathtag.com", "turn.com", "adroll.com", "perfectaudience.com", "rtbhouse.com", "yandex.ru/ads", "an.yandex.ru", "mc.yandex.ru", "adriver.ru", "begun.ru", "mail.ru/counter", "top.mail.ru", "ad.mail.ru", "baidu.com/hm.js", "hm.baidu.com", "cnzz.com", "umeng.com", "pos.baidu.com", "adsafeprotected.com", "doubleverify.com", "integralads.com", "serving-sys.com", "flashtalking.com", "eyeota.com", "id5-sync.com", "adition.com", "improvedigital.com", "undertone.com", "conversantmedia.com", "valueclick.com", "fastclick.net", "tradedoubler.com", "zanox.com", "awin1.com", "shareasale.com", "impact.com", "impactradius.com", "linksynergy.com", "cj.com", "anrdoezrs.net", "dpbolvw.net", "jdoqocy.com", "tkqlhce.com", "kqzyfj.com", "clickbank.net", "popads.net", "popcash.net", "propellerads.com", "exoclick.com", "juicyads.com", "trafficjunky.net", "trafficfactory.biz", "adcash.com", "revcontent.com", "mgid.com", "zemanta.com", "content.ad", "nativeads.com", "plista.com", "ligatus.com", "adblade.com", "infolinks.com", "intellitxt.com", "kontera.com", "bidvertiser.com", "adk2.com", "adbrite.com", "buysellads.com", "carbonads.com", "carbonads.net", "serving.carbonads.com", "ads.reddit.com", "events.reddit.com", "ad.doubleclick.net", "stats.g.doubleclick.net", "securepubads.g.doubleclick.net", "ads.youtube.com", "adserver.com", "adserver.snapads.com", "sc-static.net", "tr.snapchat.com", "analytics.snapchat.com", "clarity.ms", "bat.bing.com", "ads.microsoft.com", "optimizely.com", "vwo.com", "abtasty.com", "chartbeat.com", "chartbeat.net", "parsely.com", "comscore.com", "sitemeter.com", "statcounter.com", "histats.com", "addthis.com", "sharethis.com", "disqusads.com", "zedo.com", "yllix.com", "adspirit.de", "emxdgt.com", "betweendigital.com", "gemius.pl", "gemius.com", "adform.com", "ayads.co", "onetag-sys.com", "pubmine.com", "ezoic.net", "ezodn.com", "mediavine.com", "adthrive.com", "cafemedia.com", "tynt.com", "360yield.com"]

## true si l'hôte de l'URL est (ou est un sous-domaine de) un domaine de la liste.
static func is_ad_url(url: String) -> bool:
	var h := host_of(url)
	if h == "": return false
	var path := url.substr(url.find(h) + h.length()) if url.contains(h) else ""
	for d: String in AD_DOMAINS:
		var slash := d.find("/")
		var dom := d.substr(0, slash) if slash >= 0 else d
		if h == dom or h.ends_with("." + dom):
			if slash < 0 or path.begins_with(d.substr(slash)): return true
	return false

static func host_of(url: String) -> String:
	var s := url
	var i := s.find("://")
	if i >= 0: s = s.substr(i + 3)
	for c in ["/", "?", "#", ":"]:
		var j := s.find(c)
		if j >= 0: s = s.substr(0, j)
	var at := s.rfind("@")
	if at >= 0: s = s.substr(at + 1)
	return s.to_lower()

## À appeler pour chaque requête : renvoie true (et compte) si elle doit être bloquée.
func should_block(url: String) -> bool:
	if adblock and is_ad_url(url):
		blocked += 1; return true
	return false

# ------------------------------------------------------------ Coffre de mots de passe (AES-256-CBC + HMAC)
## Format : {"salt","iv","mac","data"} en base64. Le contenu clair n'est jamais écrit.
static func _derive(pw: String, salt: PackedByteArray) -> PackedByteArray:
	var k := pw.to_utf8_buffer() + salt
	for i in 3000:
		var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(k + salt); k = h.finish()
	return k

static func vault_encrypt(entries: Array, pw: String) -> Dictionary:
	var c := Crypto.new()
	var salt := c.generate_random_bytes(16); var iv := c.generate_random_bytes(16)
	var key := _derive(pw, salt)
	var plain := JSON.stringify(entries).to_utf8_buffer()
	var pad := 16 - plain.size() % 16
	for i in pad: plain.append(pad)
	var aes := AESContext.new(); aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	var enc := aes.update(plain); aes.finish()
	var mac := c.hmac_digest(HashingContext.HASH_SHA256, key, iv + enc)
	return {"salt": Marshalls.raw_to_base64(salt), "iv": Marshalls.raw_to_base64(iv), "mac": Marshalls.raw_to_base64(mac), "data": Marshalls.raw_to_base64(enc)}

## Renvoie le tableau d'entrées, ou null si le mot de passe maître est faux / le fichier altéré.
static func vault_decrypt(v: Dictionary, pw: String):
	if not (v.has("salt") and v.has("iv") and v.has("mac") and v.has("data")): return null
	var salt := Marshalls.base64_to_raw(v["salt"]); var iv := Marshalls.base64_to_raw(v["iv"])
	var enc := Marshalls.base64_to_raw(v["data"])
	var key := _derive(pw, salt)
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, iv + enc)
	if mac != Marshalls.base64_to_raw(v["mac"]) or enc.size() == 0 or enc.size() % 16 != 0: return null
	var aes := AESContext.new(); aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	var plain := aes.update(enc); aes.finish()
	var pad := int(plain[plain.size() - 1])
	if pad < 1 or pad > 16: return null
	plain.resize(plain.size() - pad)
	var j = JSON.parse_string(plain.get_string_from_utf8())
	return j if j is Array else null

# ------------------------------------------------------------ Persistance
func _w(name: String, data) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data)); f.close()

func _r(name: String):
	if not FileAccess.file_exists(dir + "/" + name): return null
	return JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + name))

## Les onglets privés ne sont jamais enregistrés ; les téléchargements ne sont pas conservés.
func save() -> void:
	_w("bookmarks.json", bookmarks)
	_w("history.json", history)
	if not primary: return
	var keep := tabs.filter(func(t): return not t["private"])
	var act := 0
	if not tabs.is_empty() and not tabs[active]["private"]: act = maxi(0, keep.find(tabs[active]))
	_w("state.json", {"tabs": keep.map(func(t): return {"url": t["url"], "title": t["title"]}), "active": act,
		"desktop": desktop_mode, "adblock": adblock, "blocked": blocked})

func load_all() -> void:
	var s = _r("state.json")
	if s is Dictionary and primary:
		desktop_mode = bool(s.get("desktop", true)); adblock = bool(s.get("adblock", true)); blocked = int(s.get("blocked", 0))
		tabs.clear()
		for t in s.get("tabs", []): open_tab(str(t.get("url", HOME)), false, false); tabs[-1]["title"] = str(t.get("title", ""))
		active = clampi(int(s.get("active", 0)), 0, maxi(0, tabs.size() - 1))
	var b = _r("bookmarks.json"); if b is Array: bookmarks = b
	var h = _r("history.json"); if h is Array: history = h
	if tabs.is_empty(): open_tab()

func vault_save(entries: Array, pw: String) -> void: _w("vault.json", vault_encrypt(entries, pw))
func vault_exists() -> bool: return FileAccess.file_exists(dir + "/vault.json")
func vault_load(pw: String): 
	var v = _r("vault.json")
	return vault_decrypt(v, pw) if v is Dictionary else null
