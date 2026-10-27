extends RefCounted
## One licensed Gothic family keeps Japanese, kana and Korean aligned.

const HEADING_PATH: String = "res://assets/fonts/NotoSansCJKjp-Regular.otf"
const BODY_PATH: String = HEADING_PATH
const JAPANESE_PATH: String = HEADING_PATH
const READING_PATH: String = HEADING_PATH
const FALLBACK_PATH: String = HEADING_PATH

static var _fallback: Font
static var _theme: Theme

static func _font_file(path: String) -> Font:
	# Source QA can load the official OTF before the editor imports it. Exported
	# games can instead resolve the imported FontFile from the packed resource.
	if FileAccess.file_exists(path):
		var file: FontFile = FontFile.new()
		if file.load_dynamic_font(path) == OK and not file.data.is_empty():
			return file
	if ResourceLoader.exists(path):
		return load(path) as Font
	return null

static func body() -> Font:
	return fallback()

static func heading() -> Font:
	return fallback()

static func japanese() -> Font:
	return fallback()

static func reading() -> Font:
	return fallback()

static func fallback() -> Font:
	if _fallback == null:
		_fallback = _font_file(FALLBACK_PATH)
		if _fallback == null: _fallback = ThemeDB.fallback_font
	return _fallback

static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = body()
		_theme.default_font_size = 20
	return _theme
