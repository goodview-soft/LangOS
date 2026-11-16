class_name UiTheme extends RefCounted
## Police lissée partagée par tout le HUD, les menus, l'inventaire et le livre de recettes (comme le chat) :
## bien plus lisible que la police pixel brute à petite taille.

static var _font: Font
static var _theme: Theme

static func font() -> Font:
	if _font == null:
		var f: Font = ThemeDB.fallback_font.duplicate()
		if f is FontFile:
			(f as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			(f as FontFile).hinting = TextServer.HINTING_LIGHT
		_font = f
	return _font

static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = font()
		_theme.default_font_size = 10
	return _theme
