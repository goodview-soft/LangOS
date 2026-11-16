extends RefCounted
## Système de design partagé, calqué sur GNOME libadwaita (HIG) : jetons, échelle typographique (Inter), icônes (Lucide) et gabarits communs.
## Tout dérive de main._p() (thème clair/sombre), main.ACCENT et main._rad() : rien de codé en dur dans les applications.
## Usage : const UI = preload("res://apps/ui.gd")  puis  UI.header_bar(), UI.row(), UI.icon_btn("plus", "Ajouter") ...

static var m                      # main.gd, renseigné au démarrage du bureau

# Espacements (libadwaita : multiples de 6)
const S1 := 3
const S2 := 6
const S3 := 12
const S4 := 18
const S5 := 24
# Échelle typographique unique (libadwaita : title-1 20pt, title-2 15pt, title-4 13pt, heading/body 11pt, caption 9pt)
const T_BIG := 26        # titre d'une page d'état
const T_TITLE := 20      # titre de page
const T_HEAD := 17       # titre de section
const T_WIN := 15        # titre de fenêtre et en-tête de groupe (gras)
const T_BODY := 15       # corps
const T_SMALL := 13      # légende
const T_TINY := 12
# Dimensions
const TOUCH := 36        # hauteur minimale des boutons à texte
const BTN := 34          # bouton-icône (libadwaita : min-height 34)
const ROW_H := 50        # ligne de liste encadrée
const BAR_H := 46        # barre d'en-tête
const NARROW := 700.0    # sous cette largeur : un seul panneau
const CLAMP_W := 600.0   # largeur maximale d'une page de préférences

## Écran tactile (Android ou écran tactile détecté) : cibles ≥ 44 px, barres de défilement larges.
static func touch() -> bool:
	return OS.get_name() == "Android" or DisplayServer.is_touchscreen_available()

## Taille de cible : au moins 44 px sur tactile.
static func tp(n: float) -> float:
	return maxf(n, 44.0) if touch() else n

## Focus clavier visible et discret (contour d'accent) ; sur tactile les boutons gardent FOCUS_NONE (le clavier maison ne perd pas son champ).
static func focus_mode_btn() -> int:
	return Control.FOCUS_NONE if touch() else Control.FOCUS_ALL

static func p(k: String) -> Color:
	if m == null: return PAL_FALLBACK.get(k, Color("888888"))
	return m._p(k)

const PAL_FALLBACK := {"win": Color("222226"), "card": Color("343438"), "field": Color("1d1d20"), "view": Color("1d1d20"), "header": Color("2e2e32"), "sidebar": Color("2e2e32"),
	"popup": Color("36363a"), "text": Color("ffffff"), "muted": Color("a5a5a9"), "edge": Color(1, 1, 1, 0.15), "ov": Color(1, 1, 1), "destructive": Color("c01c28"),
	"ok": Color("8ff0a4"), "warn": Color("f8e45c"), "err": Color("ff7b63")}

static func accent() -> Color:
	return m.ACCENT if m != null else Color("3584e4")

## Rayon des fenêtres et des cartes (réglable, 12 par défaut).
static func rad(extra := 0) -> int:
	return maxi(0, (int(m.set_cfg.get("radius", 12)) if m != null else 12) + extra)

## Rayon des boutons et des champs (libadwaita : 9), borné par le réglage de l'utilisateur.
static func rad_btn() -> int:
	return mini(9, rad())

static func light() -> bool:
	return m != null and bool(m.set_cfg.get("light", false))

## Couleurs sémantiques (contrastées dans les deux thèmes)
static func ok() -> Color: return p("ok")
static func warn() -> Color: return p("warn")
static func err() -> Color: return p("err")
static func muted_c() -> Color: return p("muted")
## Voile de la couleur du texte (libadwaita : currentColor à 7 / 10 / 15 / 30 %).
static func veil(a: float) -> Color: return Color(p("ov"), a)
## Texte lisible posé sur une couleur de fond donnée (noir ou blanc selon la luminance).
static func on(bg: Color) -> Color:
	return Color("0b1220") if bg.get_luminance() > 0.42 else Color.WHITE

## Rapport de contraste WCAG entre deux couleurs opaques.
static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a); var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
static func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

# ---------------------------------------------------------------- Police (Inter, licence OFL)
static var _fonts := {}
const FONT_PATH := "res://fonts/InterVariable.ttf"

## Police Inter à la graisse voulue (400 normal, 600 demi-gras, 700 gras, 800 titres) ; repli sur une police du système.
static func font(weight := 400, italic := false) -> Font:
	var key := "%d%s" % [weight, "i" if italic else ""]
	if _fonts.has(key): return _fonts[key]
	if not _fonts.has("base"):
		var sys := SystemFont.new(); sys.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "Ubuntu", "Roboto", "DejaVu Sans"])
		var base: Font = sys
		if ResourceLoader.exists(FONT_PATH):
			var ff = load(FONT_PATH)
			if ff is FontFile: ff.fallbacks = [sys]; base = ff
		_fonts["base"] = base; _fonts["inter"] = base is FontFile
	var f: Font = _fonts["base"]
	if _fonts["inter"]:
		var fv := FontVariation.new(); fv.base_font = f
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		if italic: fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2.ZERO)
		f = fv
	elif weight != 400 or italic:
		var sv := SystemFont.new(); sv.font_names = (_fonts["base"] as SystemFont).font_names; sv.font_weight = weight; sv.font_italic = italic; f = sv
	_fonts[key] = f
	return f

static func mono() -> Font:
	if not _fonts.has("mono"):
		var s := SystemFont.new(); s.font_names = PackedStringArray(["JetBrains Mono", "Adwaita Mono", "Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		_fonts["mono"] = s
	return _fonts["mono"]

# ---------------------------------------------------------------- Icônes (Lucide, licence ISC)
## Icône Lucide (trait blanc, teintée par modulate ou par la couleur d'icône du thème) : UI.icon("search").
static func icon(name: String) -> Texture2D:
	var path := "res://icons/lucide/%s.svg" % name
	return load(path) if ResourceLoader.exists(path) else null

## Image d'icône teintée par le thème (texte ou texte atténué).
static func icon_rect(name: String, sz := 16, dim := false) -> TextureRect:
	var t := TextureRect.new(); t.texture = icon(name); t.custom_minimum_size = Vector2(sz, sz)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	on_theme(t, func(): t.modulate = p("muted") if dim else p("text"))
	return t

## Petits pictogrammes du thème (interrupteur, case, flèches), dessinés à la taille exacte pour rester nets.
static var _glyphs := {}
const GLYPH_PATHS := {"chevron-down": "m6 9 6 6 6-6", "chevron-right": "m9 18 6-6-6-6", "check": "M20 6 9 17l-5-5", "x": "M18 6 6 18M6 6l12 12"}
static func _svg(key: String, w: int, h: int, body: String) -> ImageTexture:
	if _glyphs.has(key): return _glyphs[key]
	var im := Image.new()
	im.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [w, h, w, h, body])
	var t := ImageTexture.create_from_image(im); _glyphs[key] = t
	return t

static func glyph(name: String, c: Color, sz := 16) -> ImageTexture:
	var k := sz / 24.0
	return _svg("%s|%s|%d" % [name, c.to_html(), sz], sz, sz, '<g transform="scale(%f)"><path d="%s" fill="none" stroke="#%s" stroke-opacity="%f" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g>' % [k, GLYPH_PATHS[name], c.to_html(false), c.a])

static func blank(sz := 16) -> ImageTexture:
	return _svg("blank|%d" % sz, sz, sz, "")

## Interrupteur libadwaita (46 x 26) : piste grise ou d'accent, bouton rond blanc.
static func switch_tex(checked: bool, disabled := false) -> ImageTexture:
	var track := accent() if checked else p("ov")
	var op := (1.0 if checked else 0.15) * (0.5 if disabled else 1.0)
	return _svg("sw|%s|%s|%s|%s" % [checked, disabled, track.to_html(false), light()], 46, 26,
		'<rect width="46" height="26" rx="13" fill="#%s" fill-opacity="%f"/><circle cx="%d" cy="13" r="10" fill="#%s" fill-opacity="%f"/>' % [track.to_html(false), op, 33 if checked else 13, "ffffff" if checked or light() else "d6d6d8", 0.6 if disabled else 1.0])

## Case à cocher / bouton radio libadwaita (20 x 20).
static func check_tex(checked: bool, radio := false, disabled := false) -> ImageTexture:
	var a := accent(); var o := p("ov"); var rx := 10 if radio else 6
	var body := ""
	if checked:
		body = '<rect x="1" y="1" width="18" height="18" rx="%d" fill="#%s"/>' % [rx - 1, a.to_html(false)]
		body += '<circle cx="10" cy="10" r="3.5" fill="#%s"/>' % on(a).to_html(false) if radio else '<path d="M5.5 10.5l3 3 6-6.5" fill="none" stroke="#%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' % on(a).to_html(false)
	else:
		body = '<rect x="2" y="2" width="16" height="16" rx="%d" fill="none" stroke="#%s" stroke-opacity="0.3" stroke-width="2"/>' % [rx - 2, o.to_html(false)]
	if disabled: body = '<g opacity="0.5">%s</g>' % body
	return _svg("ck|%s|%s|%s|%s|%s" % [checked, radio, disabled, a.to_html(false), o.to_html(false)], 20, 20, body)

## Bouton rond d'un curseur (20 x 20).
## Contour de focus clavier (accent, sans remplissage).
static func focus_box(r := -1) -> StyleBoxFlat:
	var s := box(Color(0, 0, 0, 0), rad_btn() if r < 0 else r, Color(accent(), 0.8), 2)
	return s

static func knob_tex(hi := false) -> ImageTexture:
	return _svg("knob|%s|%s" % [hi, light()], 20, 20, '<circle cx="10" cy="10" r="9" fill="#%s" stroke="#000" stroke-opacity="0.25" stroke-width="1"/>' % ("ffffff" if hi or light() else "dededf"))

# ---------------------------------------------------------------- Styles
static func box(c: Color, r := -1, bc := Color(0, 0, 0, 0), bw := 0, margin := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(rad() if r < 0 else r)
	if bw > 0: s.border_color = bc; s.set_border_width_all(bw)
	if margin >= 0: s.set_content_margin_all(margin)
	return s

## Carte libadwaita : fond de carte, rayon 12, ombre légère à la place d'une bordure.
static func card_box(margin := S3, alt := false) -> StyleBoxFlat:
	var s := box(p("field") if alt else p("card"), rad(), Color(0, 0, 0, 0), 0, margin)
	if light() or alt: s.border_color = Color(p("ov"), 0.08 if light() else 0.1); s.set_border_width_all(1)
	if light(): s.shadow_color = Color(0, 0, 0.02, 0.07); s.shadow_size = 3; s.shadow_offset = Vector2(0, 1)
	return s

## Champ de saisie libadwaita : fond voilé à 10 %, sans bordure ; contour d'accent au focus.
static func entry_box(focus := false) -> StyleBoxFlat:
	var s := box(veil(0.1), rad_btn())
	s.content_margin_left = 10; s.content_margin_right = 10; s.content_margin_top = 7; s.content_margin_bottom = 7
	if focus: s.bg_color = Color(0, 0, 0, 0); s.border_color = Color(accent(), 0.6); s.set_border_width_all(2)   # dessiné par-dessus le fond normal
	return s

## Fond d'une barre (en-tête, recherche) : couleur de headerbar et filet inférieur.
static func bar_box() -> StyleBoxFlat:
	var s := box(p("header"), 0); s.border_width_bottom = 1; s.border_color = p("edge")
	s.content_margin_left = S2; s.content_margin_right = S2; s.content_margin_top = S2; s.content_margin_bottom = S2 + 1
	return s

# ---------------------------------------------------------------- Recoloration à chaud
## Enregistre fn() : appelée tout de suite, puis à chaque changement de thème, d'accent ou de rayon (groupe « themed », voir main._restyle).
static func on_theme(node: Node, fn: Callable) -> void:
	var a: Array = node.get_meta("_themed", []); a.append(fn); node.set_meta("_themed", a)
	node.add_to_group("themed"); fn.call()

## Style thématique : maker() renvoie un StyleBox, réappliqué sur « slot » à chaque rafraîchissement.
static func style(node: Control, slot: String, maker: Callable) -> void:
	on_theme(node, func(): node.add_theme_stylebox_override(slot, maker.call()))

## Réapplique tous les styles thématiques des nœuds vivants (appelé par main._restyle).
static func refresh(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group("themed"):
		for f in n.get_meta("_themed", []):
			if f.is_valid(): f.call()

# ---------------------------------------------------------------- Textes
static func label(t: String, sz := T_BODY, variation := "") -> Label:
	var l := Label.new(); l.text = t
	if sz != T_BODY: l.add_theme_font_size_override("font_size", sz)
	if variation != "": l.theme_type_variation = variation
	return l

static func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 10; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return l

static func title(t: String) -> Label: return label(t, T_TITLE, "Title")
static func head(t: String) -> Label: return label(t, T_HEAD, "Head")
## En-tête de groupe / titre de fenêtre : corps gras.
static func heading(t: String) -> Label: return label(t, T_WIN, "Heading")
static func body(t: String) -> Label: return _wrap(label(t))
static func small(t: String) -> Label: return label(t, T_SMALL, "Caption")
static func muted(l: Control) -> Control:
	l.theme_type_variation = "Muted"; return l
static func note(t: String) -> Label: return _wrap(label(t, T_SMALL, "Caption"))
static func status_label(t: String, kind := "ok") -> Label:
	var l := label(t, T_SMALL, {"ok": "Ok", "warn": "Warn", "err": "Err"}.get(kind, "Ok")); return l

# ---------------------------------------------------------------- Boutons
## Bouton à texte : plat par défaut, « suggested » (accent) si primary.
static func button(t: String, primary := false, w := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = focus_mode_btn()
	b.theme_type_variation = "Accent" if primary else "Flat"
	b.custom_minimum_size = Vector2(w, tp(TOUCH)); return b

## Bouton « destructive » (rouge).
static func danger_button(t: String, w := 0) -> Button:
	var b := button(t, false, w); b.theme_type_variation = "Destructive"; return b

static func icon_button(tex: Texture2D, w := BTN, tip := "") -> Button:
	var b := Button.new(); b.focus_mode = focus_mode_btn(); b.theme_type_variation = "Flat"
	b.icon = tex; b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; b.custom_minimum_size = Vector2(tp(w), tp(BTN)); b.tooltip_text = tip; return b

## Bouton-icône Lucide avec infobulle : UI.icon_btn("plus", "Nouvelle note", callable).
static func icon_btn(name: String, tip := "", cb := Callable(), variation := "Flat", sz := BTN) -> Button:
	var b := Button.new(); b.focus_mode = focus_mode_btn(); b.theme_type_variation = variation
	b.icon = icon(name); b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 16)
	b.custom_minimum_size = Vector2(tp(sz), tp(sz)); b.tooltip_text = tip
	if cb.is_valid(): b.pressed.connect(cb)
	return b

## Pose une icône Lucide sur un bouton existant (à gauche du texte s'il y en a).
static func set_icon(b: Button, name: String, isz := 16) -> Button:
	b.icon = icon(name); b.add_theme_constant_override("icon_max_width", isz)
	if b.text == "": b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

# ---------------------------------------------------------------- Conteneurs
static func card(parent: Node = null, margin := S3, alt := false) -> VBoxContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style(pc, "panel", func(): return card_box(margin, alt))
	if parent != null: parent.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", S2); pc.add_child(v)
	return v

## Section : en-tête de groupe (gras) suivi du contenu.
static func section(parent: Node, t: String) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", S2); parent.add_child(v)
	v.add_child(label(t, T_WIN, "Section"))
	return v

## En-tête simple : titre, sous-titre discret et zone d'actions à droite (ajouter les boutons au HBox renvoyé).
static func header(t: String, sub := "") -> HBoxContainer:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", S3)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation", 0); hb.add_child(v)
	var l := head(t); l.clip_text = true; v.add_child(l)
	if sub != "": var s := small(sub); s.clip_text = true; v.add_child(s)
	return hb

## Barre d'outils : rangée qui passe à la ligne si l'espace manque.
static func toolbar() -> HFlowContainer:
	var f := HFlowContainer.new(); f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_theme_constant_override("h_separation", S2); f.add_theme_constant_override("v_separation", S2); return f

# ---------------------------------------------------------------- Gabarit : barre d'en-tête d'application
## Barre d'en-tête (AdwHeaderBar) : actions au début, titre centré (ou à gauche), actions à la fin.
## Ajouter les boutons avec UI.bar_start(bar) / UI.bar_end(bar) ; UI.bar_title(bar) est le Label du titre.
static func header_bar(t := "", centered := true) -> PanelContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style(pc, "panel", bar_box)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", S2); h.custom_minimum_size.y = BTN; pc.add_child(h)
	var a := HBoxContainer.new(); a.add_theme_constant_override("separation", S2); h.add_child(a); a.set_meta("no_flow", true)
	var l := heading(t); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT; l.custom_minimum_size.x = 10; h.add_child(l)
	var e := HBoxContainer.new(); e.add_theme_constant_override("separation", S2); h.add_child(e); e.set_meta("no_flow", true)
	pc.set_meta("start", a); pc.set_meta("title", l); pc.set_meta("end", e)
	return pc

## Séparateur fixe entre deux groupes de boutons d'une barre.
static func bar_gap(group: Control, w := S3) -> void:
	var c := Control.new(); c.custom_minimum_size = Vector2(w, 0); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; group.add_child(c)

## Ajoute un bouton-icône à un groupe de la barre (début ou fin). rare = passe dans le menu ⋮ sous 700 px.
static func bar_act(bar: Control, group: Control, icon_name: String, tip: String, cb: Callable, rare := false) -> Button:
	var b := icon_btn(icon_name, tip, cb); group.add_child(b)
	var a: Array = bar.get_meta("acts", []); a.append([b, tip, cb, rare, icon_name]); bar.set_meta("acts", a)
	return b

## Entrée supplémentaire du menu ⋮ (toujours présente) : [libellé, callable].
static func bar_item(bar: Control, label_: String, cb: Callable) -> void:
	var a: Array = bar.get_meta("items", []); a.append([label_, cb]); bar.set_meta("items", a)

## Termine la barre : bouton ⋮ (popup) avec les entrées supplémentaires et, sous 700 px, les actions rares.
static func bar_finish(bar: Control) -> void:
	var mb := icon_btn("ellipsis-vertical", "Menu"); bar_end(bar).add_child(mb)
	var pm := PopupMenu.new(); mb.add_child(pm)
	var fill := func():
		pm.clear(); var narrow: bool = bar.size.x < NARROW; var n := 0
		for a in bar.get_meta("acts", []):
			a[0].visible = not (narrow and a[3])
			if narrow and a[3]: pm.add_item(a[1], n); pm.set_item_metadata(n, a[2]); n += 1
		for it in bar.get_meta("items", []): pm.add_item(it[0], n); pm.set_item_metadata(n, it[1]); n += 1
		mb.visible = n > 0
	pm.id_pressed.connect(func(i: int): var cb: Callable = pm.get_item_metadata(pm.get_item_index(i)); cb.call())
	mb.pressed.connect(func(): fill.call(); if pm.item_count > 0: pm.position = Vector2i(mb.get_screen_position() + Vector2(mb.size.x - 200, mb.size.y)); pm.popup())
	bar.resized.connect(fill); fill.call()
	bar.set_meta("fill", fill)

static func bar_start(bar: Control) -> HBoxContainer: return bar.get_meta("start")
static func bar_end(bar: Control) -> HBoxContainer: return bar.get_meta("end")
static func bar_title(bar: Control) -> Label: return bar.get_meta("title")
## Remplace le titre par un contrôle central étiré (barre de chemin, champ de recherche…).
static func bar_center(bar: Control, c: Control) -> void:
	var l: Label = bar.get_meta("title"); l.visible = false
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_sibling(c)

# ---------------------------------------------------------------- Gabarit : barre latérale + contenu
## Panneau de barre latérale (fond « sidebar », filet côté contenu).
static func sidebar_panel(right := false) -> PanelContainer:
	var sp := PanelContainer.new()
	style(sp, "panel", func():
		var s := box(p("sidebar"), 0); s.border_color = p("edge"); s.set_content_margin_all(S2)
		if right: s.border_width_left = 1; s.corner_radius_bottom_right = rad(-1)
		else: s.border_width_right = 1; s.corner_radius_bottom_left = rad(-1)
		return s)
	return sp

## Disposition barre latérale + contenu (AdwNavigationSplitView) : sous 700 px un seul panneau est visible.
## UI.split_toggle(s) affiche/masque la barre latérale ; UI.split_content(s) revient au contenu en mode étroit.
static func split(side: Control, content: Control, side_w := 220) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 0)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sp := sidebar_panel(); sp.add_child(side); h.add_child(sp)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(content)
	h.set_meta("side", sp); h.set_meta("content", content); h.set_meta("side_w", side_w); h.set_meta("side_on", true); h.set_meta("narrow", false)
	h.resized.connect(func(): split_layout(h))
	split_layout(h)
	return h

static func split_narrow(h: Control) -> bool: return h.size.x < NARROW

static func split_layout(h: Control) -> void:
	var narrow := split_narrow(h)
	if narrow != bool(h.get_meta("narrow")):
		h.set_meta("narrow", narrow); h.set_meta("side_on", not narrow)   # étroit : le contenu d'abord ; large : les deux
	var sp: Control = h.get_meta("side"); var c: Control = h.get_meta("content"); var on_: bool = h.get_meta("side_on")
	sp.visible = on_; c.visible = not (narrow and on_)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	sp.custom_minimum_size.x = 0 if narrow else int(h.get_meta("side_w"))

static func split_toggle(h: Control) -> void:
	h.set_meta("side_on", not bool(h.get_meta("side_on"))); split_layout(h)

static func split_content(h: Control) -> void:
	if split_narrow(h) and bool(h.get_meta("side_on")): h.set_meta("side_on", false); split_layout(h)

## Ligne de navigation d'une barre latérale : icône + libellé, plate, sélection voilée (variation « Nav »).
static func nav_row(t: String, icon_name := "", cb := Callable()) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE; b.theme_type_variation = "Nav"
	b.focus_mode = focus_mode_btn()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.clip_text = true; b.custom_minimum_size = Vector2(0, tp(TOUCH)); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if icon_name != "": set_icon(b, icon_name)
	if cb.is_valid(): b.pressed.connect(cb)
	return b

# ---------------------------------------------------------------- Gabarit : liste encadrée de lignes
## Liste encadrée (GtkListBox « boxed-list ») : ajouter les lignes avec UI.add_row(list, UI.row(...)).
static func list_box(parent: Node = null) -> VBoxContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style(pc, "panel", func(): return card_box(0))
	if parent != null: parent.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); pc.add_child(v)
	return v

## Ligne (AdwActionRow) : icône en préfixe, titre, sous-titre, contrôle en suffixe (à droite).
static func row(t: String, sub := "", icon_name := "", suffix: Control = null) -> MarginContainer:
	var mc := MarginContainer.new(); mc.custom_minimum_size.y = ROW_H; mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_left", S3); mc.add_theme_constant_override("margin_right", S3)
	mc.add_theme_constant_override("margin_top", S2); mc.add_theme_constant_override("margin_bottom", S2)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", S3); mc.add_child(h)
	if icon_name != "": h.add_child(icon_rect(icon_name, 16))
	var tv := VBoxContainer.new(); tv.alignment = BoxContainer.ALIGNMENT_CENTER; tv.add_theme_constant_override("separation", 2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tv.custom_minimum_size.x = 110; h.add_child(tv)
	var tl := _wrap(label(t)); tv.add_child(tl)
	var sl := note(sub); sl.visible = sub != ""; tv.add_child(sl)
	if suffix != null:
		suffix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not (suffix.size_flags_horizontal & Control.SIZE_EXPAND): suffix.size_flags_horizontal = Control.SIZE_SHRINK_END
		h.add_child(suffix)
	mc.set_meta("title", tl); mc.set_meta("sub", sl); mc.set_meta("box", h)
	return mc

## Ajoute une ligne (ou tout contrôle) à une liste encadrée, précédée d'un filet de séparation.
static func add_row(list: Node, r: Control) -> Control:
	if list.get_child_count() > 0: list.add_child(HSeparator.new())
	list.add_child(r); return r

# ---------------------------------------------------------------- Gabarit : page de préférences
## Conteneur qui borne la largeur de son contenu et le centre (AdwClamp).
class Clamp extends Container:
	var max_w := 600.0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control and c.visible:
					var w := minf(size.x, max_w)
					fit_child_in_rect(c, Rect2((size.x - w) / 2.0, 0, w, size.y))
	func _get_minimum_size() -> Vector2:
		var ms := Vector2.ZERO
		for c in get_children():
			if c is Control and c.visible: ms = ms.max(c.get_combined_minimum_size())
		return ms

static func clamped(child: Control, max_w := CLAMP_W) -> Container:
	var c := Clamp.new(); c.max_w = max_w; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.add_child(child); return c

## Page de préférences (AdwPreferencesPage) : défilement vertical, colonne centrée de 600 px au plus ; y ajouter des UI.prefs_group().
static func prefs_page(parent: Node = null) -> VBoxContainer:
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var mg := MarginContainer.new(); mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mg.add_theme_constant_override("margin_left", S3); mg.add_theme_constant_override("margin_right", S3)
	mg.add_theme_constant_override("margin_top", S5); mg.add_theme_constant_override("margin_bottom", S5)
	sc.add_child(mg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", S5)
	mg.add_child(clamped(v))
	if parent != null: parent.add_child(sc)
	return v

## Groupe de préférences (AdwPreferencesGroup) : titre gras, description discrète, liste encadrée. Renvoie la liste.
static func prefs_group(page: Node, t: String, desc := "") -> VBoxContainer:
	var g := VBoxContainer.new(); g.add_theme_constant_override("separation", S3); g.size_flags_horizontal = Control.SIZE_EXPAND_FILL; page.add_child(g)
	var hd := VBoxContainer.new(); hd.add_theme_constant_override("separation", S1); g.add_child(hd)
	var tl := _wrap(heading(t)); tl.visible = t != ""; hd.add_child(tl)
	var d := note(desc); d.visible = desc != ""; hd.add_child(d)
	var list := list_box(g); list.set_meta("desc", d)
	return list

## Ajoute une phrase d'explication sous le titre d'un groupe.
static func group_note(list: Node, t: String) -> void:
	var d: Label = list.get_meta("desc")
	d.text = t if d.text == "" else d.text + "\n" + t; d.visible = true

# ---------------------------------------------------------------- Gabarit : recherche
## Champ de recherche (GtkSearchEntry) : loupe à gauche, bouton d'effacement.
static func search_field(placeholder := "Rechercher…") -> LineEdit:
	var e := LineEdit.new(); e.placeholder_text = placeholder; e.clear_button_enabled = true
	e.custom_minimum_size = Vector2(120, BTN); e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	on_theme(e, func():
		for st in ["normal", "focus"]:
			var s := entry_box(st == "focus"); s.content_margin_left = 34; e.add_theme_stylebox_override(st, s))
	e.draw.connect(func(): var t := icon("search"); if t != null: e.draw_texture_rect(t, Rect2(10, (e.size.y - 16.0) / 2.0, 16, 16), false, p("muted")))
	return e

## Barre de recherche (GtkSearchBar) : bandeau sous l'en-tête, champ centré. UI.search_entry(bar) renvoie le champ.
static func search_bar(placeholder := "Rechercher…") -> PanelContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style(pc, "panel", bar_box)
	var e := search_field(placeholder)
	pc.add_child(clamped(e, 420.0)); pc.set_meta("field", e)
	return pc

static func search_entry(bar: Control) -> LineEdit: return bar.get_meta("field")

# ---------------------------------------------------------------- Gabarit : page d'état, bandeau, toast
## Page d'état (AdwStatusPage) : grande icône atténuée, titre, description, action éventuelle.
static func status_page(icon_name: String, t: String, desc := "", action: Control = null, compact := false) -> VBoxContainer:
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", S3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if icon_name != "":
		var ic := icon_rect(icon_name, 32 if compact else 48, true); ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(ic)
	var a := _wrap(label(t, T_HEAD, "Head") if compact else label(t, T_TITLE, "Title")); a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(a)
	if desc != "":
		var b := _wrap(label(desc, T_BODY, "Muted")); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(b)
	if action != null: action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(action)
	v.set_meta("title", a)
	return v

## État vide / chargement / erreur : page d'état avec l'icône adaptée.
static func empty_state(t: String, hint := "", kind := "") -> VBoxContainer:
	var v := status_page("circle-alert" if kind == "err" else "inbox", t, hint, null, true)
	if kind == "err": (v.get_meta("title") as Label).theme_type_variation = "ErrTitle"
	return v

## Bandeau (AdwBanner) : message sur toute la largeur, bouton d'action facultatif.
static func banner(t: String, btn_text := "", cb := Callable()) -> PanelContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style(pc, "panel", func():
		var s := box(p("win").lerp(accent(), 0.3), 0); s.content_margin_left = S3; s.content_margin_right = S3; s.content_margin_top = S2; s.content_margin_bottom = S2; return s)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", S3); pc.add_child(h)
	var l := _wrap(heading(t)); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; h.add_child(l)
	if btn_text != "":
		var b := button(btn_text); b.theme_type_variation = ""; b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if cb.is_valid(): b.pressed.connect(cb)
		h.add_child(b)
	pc.set_meta("title", l)
	return pc

## Toast (AdwToast) : pastille sombre, texte blanc ; avec un second texte, carte de notification à deux lignes.
static func toast(t: String, sub := "", icon_name := "", max_w := 320.0) -> PanelContainer:
	var pc := PanelContainer.new(); pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := box(Color(0.1, 0.1, 0.11, 0.94), 99 if sub == "" else rad(), Color(1, 1, 1, 0.12), 1)
	s.content_margin_left = S4; s.content_margin_right = S4; s.content_margin_top = S3 if sub != "" else S2 + 2; s.content_margin_bottom = s.content_margin_top
	s.shadow_color = Color(0, 0, 0, 0.35); s.shadow_size = 14; s.shadow_offset = Vector2(0, 4)
	pc.add_theme_stylebox_override("panel", s)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", S3); pc.add_child(h)
	if icon_name != "":
		var ic := TextureRect.new(); ic.texture = icon(icon_name); ic.custom_minimum_size = Vector2(16, 16); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(ic)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); h.add_child(v)
	var l1 := label(t, T_BODY, "Heading"); l1.add_theme_color_override("font_color", Color.WHITE); v.add_child(l1)
	if sub != "":
		var l2 := label(sub, T_SMALL); l2.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l2.custom_minimum_size.x = max_w; v.add_child(l2)
	return pc

## Pastille colorée avec texte (étiquette d'état).
static func pill(t: String, c: Color) -> PanelContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	style(pc, "panel", func(): var b := box(Color(c, 0.18), 99, Color(c, 0.5), 1); b.content_margin_left = S3; b.content_margin_right = S3; b.content_margin_top = 2; b.content_margin_bottom = 2; return b)
	var l := label(t, T_TINY); pc.add_child(l)
	on_theme(l, func(): l.add_theme_color_override("font_color", c if c.get_luminance() < 0.6 or not light() else c.darkened(0.4)))
	return pc

static func separator() -> HSeparator:
	return HSeparator.new()

## Ajoute au thème de main les variantes de texte partagées : l'échelle typographique est définie ici, une seule fois.
static func extend_theme(th: Theme) -> void:
	var tx: Color = p("text")
	# [variante, taille, couleur, graisse]
	for v in [["Title", T_TITLE, tx, 800], ["Head", T_HEAD, tx, 700], ["Heading", T_WIN, tx, 700], ["Section", T_WIN, tx, 700],
			["Muted", T_BODY, p("muted"), 400], ["Caption", T_SMALL, p("muted"), 400],
			["Ok", T_SMALL, p("ok"), 400], ["Warn", T_SMALL, p("warn"), 400], ["Err", T_BODY, p("err"), 400], ["ErrTitle", T_HEAD, p("err"), 700]]:
		th.set_type_variation(v[0], "Label")
		th.set_color("font_color", v[0], v[2]); th.set_font_size("font_size", v[0], v[1])
		if v[3] != 400: th.set_font("font", v[0], font(v[3]))

## Couleur d'accent lisible comme texte sur le fond de fenêtre (assombrie en thème clair).
static func accent_text() -> Color:
	var a := accent()
	return a.darkened(0.35) if light() and a.get_luminance() > 0.3 else a

## Thème local d'une bulle de discussion : texte blanc sur la bulle « moi », texte normal sur l'autre.
static func bubble_bg(mine: bool) -> Color: return p("bub_me") if mine else p("bub_you")
static func bubble_theme(mine: bool) -> Theme:
	var c: Color = Color.WHITE if mine else p("text")
	var th := Theme.new()
	th.set_color("font_color", "Label", c); th.set_color("default_color", "RichTextLabel", c)
	th.set_color("font_color", "Button", c)
	return th
