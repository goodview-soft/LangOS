extends RefCounted
## Système de design partagé : espacements, typographie, couleurs sémantiques et fabriques de composants.
## Tout dérive de main._p() (thème clair/sombre), main.ACCENT et main._rad() : rien de codé en dur dans les applications.
## Usage : const UI = preload("res://apps/ui.gd")  puis  UI.card(), UI.muted(label), UI.p("ok") ...

static var m                      # main.gd, renseigné au démarrage du bureau

# Espacements
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
# Typographie
const T_TITLE := 22
const T_HEAD := 18
const T_BODY := 16
const T_SMALL := 14
const T_TINY := 12
# Hauteur minimale des cibles tactiles
const TOUCH := 40

static func p(k: String) -> Color:
	if m == null: return PAL_FALLBACK.get(k, Color("888888"))
	return m._p(k)

const PAL_FALLBACK := {"win": Color("232834"), "card": Color("1c2131"), "field": Color("171b25"), "text": Color("e5e9f0"), "muted": Color("8f9bb3"), "edge": Color(1, 1, 1, 0.1)}

static func accent() -> Color:
	return m.ACCENT if m != null else Color("5aa2ff")

static func rad(extra := 0) -> int:
	return (int(m.set_cfg.get("radius", 12)) if m != null else 12) + extra

static func light() -> bool:
	return m != null and bool(m.set_cfg.get("light", false))

## Couleurs sémantiques (contrastées dans les deux thèmes)
static func ok() -> Color: return p("ok")
static func warn() -> Color: return p("warn")
static func err() -> Color: return p("err")
static func muted_c() -> Color: return p("muted")
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

# ---------------------------------------------------------------- Styles
static func box(c: Color, r := -1, bc := Color(0, 0, 0, 0), bw := 0, margin := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(rad() if r < 0 else r)
	if bw > 0: s.border_color = bc; s.set_border_width_all(bw)
	if margin >= 0: s.set_content_margin_all(margin)
	return s

static func card_box(margin := S3, alt := false) -> StyleBoxFlat:
	return box(p("field") if alt else p("card"), rad(2), p("edge"), 1, margin)

# ---------------------------------------------------------------- Textes
static func label(t: String, sz := T_BODY, variation := "") -> Label:
	var l := Label.new(); l.text = t
	if sz != T_BODY: l.add_theme_font_size_override("font_size", sz)
	if variation != "": l.theme_type_variation = variation
	return l

static func title(t: String) -> Label: return label(t, T_TITLE, "Title")
static func head(t: String) -> Label: return label(t, T_HEAD, "Head")
static func body(t: String) -> Label:
	var l := label(t); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 10; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return l
static func small(t: String) -> Label: return muted(label(t, T_SMALL))
static func muted(l: Control) -> Control:
	l.theme_type_variation = "Muted"; return l
static func note(t: String) -> Label:
	var l := label(t, T_SMALL, "Muted"); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 10; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return l
static func status_label(t: String, kind := "ok") -> Label:
	var l := label(t, T_SMALL, {"ok": "Ok", "warn": "Warn", "err": "Err"}.get(kind, "Ok")); return l

# ---------------------------------------------------------------- Boutons
static func button(t: String, primary := false, w := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "Accent" if primary else "Flat"
	b.custom_minimum_size = Vector2(w, TOUCH); return b

static func icon_button(icon: Texture2D, w := TOUCH, tip := "") -> Button:
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.theme_type_variation = "Flat"
	b.icon = icon; b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; b.custom_minimum_size = Vector2(w, TOUCH); b.tooltip_text = tip; return b

# ---------------------------------------------------------------- Conteneurs
static func card(parent: Node = null, margin := S3, alt := false) -> VBoxContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", card_box(margin, alt))
	if parent != null: parent.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", S2); pc.add_child(v)
	return v

## Section : titre en petites capitales d'accent suivi du contenu.
static func section(parent: Node, t: String) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", S2); parent.add_child(v)
	var h := label(t.to_upper(), T_TINY, "Section"); v.add_child(h)
	return v

## En-tête d'application : titre, sous-titre discret et zone d'actions à droite.
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

static func search_field(placeholder := "Rechercher…") -> LineEdit:
	var e := LineEdit.new(); e.placeholder_text = placeholder; e.clear_button_enabled = true
	e.custom_minimum_size = Vector2(120, TOUCH); e.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return e

## État vide / chargement / erreur : message centré avec une courte explication.
static func empty_state(t: String, hint := "", kind := "") -> VBoxContainer:
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", S2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var a := body(t); a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if kind == "err": a.theme_type_variation = "Err"
	v.add_child(a)
	if hint != "":
		var b := note(hint); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(b)
	return v

## Pastille colorée avec texte (étiquette d'état).
static func pill(t: String, c: Color) -> PanelContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := box(Color(c, 0.18), 99, Color(c, 0.5), 1); sb.content_margin_left = S3; sb.content_margin_right = S3; sb.content_margin_top = 2; sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var l := label(t, T_TINY); l.add_theme_color_override("font_color", c if c.get_luminance() < 0.6 or not light() else c.darkened(0.4)); pc.add_child(l); return pc

static func separator() -> HSeparator:
	return HSeparator.new()

## Ajoute au thème de main les variantes partagées (Title, Head, Muted, Section, Ok/Warn/Err, Card, Field).
static func extend_theme(th: Theme) -> void:
	var tx: Color = p("text")
	for pair in [["Title", T_TITLE, tx], ["Head", T_HEAD, tx], ["Muted", T_BODY, p("muted")], ["Section", T_TINY, accent_text()],
			["Ok", T_SMALL, p("ok")], ["Warn", T_SMALL, p("warn")], ["Err", T_BODY, p("err")]]:
		th.set_type_variation(pair[0], "Label")
		th.set_color("font_color", pair[0], pair[2]); th.set_font_size("font_size", pair[0], pair[1])
	# Variante Muted pour boutons / cases : texte discret
	th.set_type_variation("Muted", "Label")

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
