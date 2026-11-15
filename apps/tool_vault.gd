extends Control
const UI = preload("res://apps/ui.gd")
## Coffre à mots de passe local, chiffré AES-256-CBC + HMAC-SHA256 (clé dérivée du mot de passe maître).

const PATH := "user://vault.bin"
const MAGIC := "LVT1"
const ITER := 20000

var master := ""
var entries: Array = []          # [{n, u, p, note}]
var ui: VBoxContainer
var msg: Label

# ---------- crypto (statique, testable) ----------
static func _derive(pw: String, salt: PackedByteArray) -> Array:
	var c := Crypto.new()
	var k := salt
	var pwb := pw.to_utf8_buffer()
	for i in ITER: k = c.hmac_digest(HashingContext.HASH_SHA256, pwb, k)
	return [c.hmac_digest(HashingContext.HASH_SHA256, k, "enc".to_utf8_buffer()), c.hmac_digest(HashingContext.HASH_SHA256, k, "mac".to_utf8_buffer())]

static func encrypt(plain: String, pw: String) -> PackedByteArray:
	var c := Crypto.new()
	var salt := c.generate_random_bytes(16); var iv := c.generate_random_bytes(16)
	var keys := _derive(pw, salt)
	var data := plain.to_utf8_buffer()
	var pad := 16 - data.size() % 16
	for i in pad: data.append(pad)
	var aes := AESContext.new(); aes.start(AESContext.MODE_CBC_ENCRYPT, keys[0], iv)
	var ct := aes.update(data); aes.finish()
	var body := salt + iv + ct
	var mac := c.hmac_digest(HashingContext.HASH_SHA256, keys[1], body)
	return MAGIC.to_utf8_buffer() + mac + body

## Renvoie le texte clair, ou null si mot de passe faux / fichier altéré.
static func decrypt(blob: PackedByteArray, pw: String) -> Variant:
	if blob.size() < 4 + 32 + 32 + 16 or blob.slice(0, 4).get_string_from_utf8() != MAGIC: return null
	var mac := blob.slice(4, 36); var body := blob.slice(36)
	var salt := body.slice(0, 16); var iv := body.slice(16, 32); var ct := body.slice(32)
	if ct.size() % 16 != 0: return null
	var keys := _derive(pw, salt)
	var c := Crypto.new()
	if not c.constant_time_compare(mac, c.hmac_digest(HashingContext.HASH_SHA256, keys[1], body)): return null
	var aes := AESContext.new(); aes.start(AESContext.MODE_CBC_DECRYPT, keys[0], iv)
	var pt := aes.update(ct); aes.finish()
	var pad := pt[pt.size() - 1]
	if pad < 1 or pad > 16: return null
	return pt.slice(0, pt.size() - pad).get_string_from_utf8()

static func gen_password(n: int, symbols := true) -> String:
	var chars := "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	if symbols: chars += "!@#$%&*?-_+="
	var rb := Crypto.new().generate_random_bytes(n * 2)
	var s := ""
	for i in n: s += chars[rb[i] % chars.length()]
	return s

# ---------- interface ----------
func _ready() -> void:
	ui = VBoxContainer.new(); ui.set_anchors_preset(Control.PRESET_FULL_RECT); ui.add_theme_constant_override("separation", 8); add_child(ui)
	_lock_screen()

func _clear() -> void:
	for c in ui.get_children(): c.queue_free()

func _btn(t: String, f: Callable, w := 0) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size = Vector2(w, 48); b.pressed.connect(f); return b

func _lock_screen() -> void:
	_clear(); master = ""; entries = []
	var exists := FileAccess.file_exists(PATH)
	var l := Label.new(); l.text = "Coffre verrouillé" if exists else "Crée ton coffre : choisis un mot de passe maître.\nIl ne peut pas être récupéré s'il est perdu."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.add_theme_font_size_override("font_size", 20); ui.add_child(l)
	var pw := LineEdit.new(); pw.secret = true; pw.placeholder_text = "Mot de passe maître"; pw.custom_minimum_size.y = 52; ui.add_child(pw)
	var pw2: LineEdit = null
	if not exists:
		pw2 = LineEdit.new(); pw2.secret = true; pw2.placeholder_text = "Confirmer"; pw2.custom_minimum_size.y = 52; ui.add_child(pw2)
	msg = Label.new(); msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ui.add_child(msg)
	var go := func():
		if pw.text.length() < 4: msg.text = "Au moins 4 caractères."; return
		if exists:
			var r: Variant = decrypt(FileAccess.get_file_as_bytes(PATH), pw.text)
			if r == null: msg.text = "Mot de passe incorrect."; return
			var d: Variant = JSON.parse_string(r)
			entries = d if d is Array else []
		else:
			if pw.text != pw2.text: msg.text = "Les deux mots de passe diffèrent."; return
		master = pw.text; _save(); _list_screen()
	ui.add_child(_btn("Déverrouiller" if exists else "Créer le coffre", go))
	pw.text_submitted.connect(func(_t): go.call())

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_buffer(encrypt(JSON.stringify(entries), master))

func _list_screen() -> void:
	_clear()
	var hbar := UI.header_bar("Coffre", false); ui.add_child(hbar)
	var s := LineEdit.new(); s.placeholder_text = "Rechercher…"; s.custom_minimum_size = Vector2(100, UI.BTN); UI.bar_center(hbar, s)
	UI.bar_act(hbar, UI.bar_end(hbar), "plus", "Ajouter une entrée", func(): _edit_screen(-1))
	UI.bar_act(hbar, UI.bar_end(hbar), "lock", "Verrouiller", _lock_screen)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.add_child(sc)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(box)
	var fill := func(q: String):
		for c in box.get_children(): c.queue_free()
		for i in entries.size():
			var e: Dictionary = entries[i]
			if q != "" and not (e.n.to_lower().contains(q.to_lower()) or e.u.to_lower().contains(q.to_lower())): continue
			var b := _btn("%s   %s" % [e.n, e.u], func(): _edit_screen(i)); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.clip_text = true; box.add_child(b)
		if box.get_child_count() == 0:
			box.add_child(UI.empty_state("Aucune entrée", "Ajoutez un écran avec « + Ajouter »."))
	s.text_changed.connect(fill); fill.call("")

func _edit_screen(idx: int) -> void:
	_clear()
	var e: Dictionary = entries[idx] if idx >= 0 else {"n": "", "u": "", "p": "", "note": ""}
	var f := {}
	for k in [["n", "Site / nom"], ["u", "Identifiant"], ["p", "Mot de passe"], ["note", "Note"]]:
		var le := LineEdit.new(); le.placeholder_text = k[1]; le.text = e[k[0]]; le.custom_minimum_size.y = 48; ui.add_child(le); f[k[0]] = le
	var show := CheckBox.new(); show.text = "Afficher le mot de passe"; show.custom_minimum_size.y = 44
	f["p"].secret = true; show.toggled.connect(func(on): f["p"].secret = not on); ui.add_child(show)
	var gr := HBoxContainer.new(); gr.add_theme_constant_override("separation", 6); ui.add_child(gr)
	var ln := SpinBox.new(); ln.min_value = 8; ln.max_value = 64; ln.value = 16; ln.custom_minimum_size = Vector2(110, 48); gr.add_child(ln)
	var gb := _btn("Générer un mot de passe", func(): f["p"].text = gen_password(int(ln.value)); show.button_pressed = true); gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; gr.add_child(gb)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); ui.add_child(row)
	var ok := _btn("Enregistrer", func():
		var ne := {"n": f.n.text, "u": f.u.text, "p": f.p.text, "note": f.note.text}
		if idx >= 0: entries[idx] = ne
		else: entries.append(ne)
		_save(); _list_screen())
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(ok)
	var cp := _btn("Copier le mot de passe", func(): preload("res://apps/clipboard.gd").secret = f.p.text; DisplayServer.clipboard_set(f.p.text)); cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(cp)
	var row2 := HBoxContainer.new(); row2.add_theme_constant_override("separation", 6); ui.add_child(row2)
	var back := _btn("Retour", _list_screen); back.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row2.add_child(back)
	if idx >= 0:
		var del := _btn("Supprimer", func(): entries.remove_at(idx); _save(); _list_screen()); del.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row2.add_child(del)
