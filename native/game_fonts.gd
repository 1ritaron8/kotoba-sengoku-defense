extends RefCounted
## Traditional Korean Myeongjo and Japanese brush lettering, with clear kana.

const HEADING_PATH: String = "res://assets/fonts/NanumMyeongjo-ExtraBold.ttf"
const BODY_PATH: String = "res://assets/fonts/NanumMyeongjo-Bold.ttf"
const JAPANESE_PATH: String = "res://assets/fonts/YujiSyuku-Regular.ttf"
const READING_PATH: String = "res://assets/fonts/KleeOne-SemiBold.ttf"
const FALLBACK_PATH: String = "res://assets/fonts/NotoSerifCJKjp-Medium.otf"

static var _heading: Font
static var _body: Font
static var _japanese: Font
static var _reading: Font
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
	if _body == null:
		_body = _font_file(BODY_PATH)
		if _body == null:
			_body = ThemeDB.fallback_font
		else:
			_body.fallbacks = [japanese(),fallback()]
	return _body

static func heading() -> Font:
	if _heading == null:
		_heading = _font_file(HEADING_PATH)
		if _heading == null:
			_heading = body()
		else:
			_heading.fallbacks = [japanese(),fallback()]
	return _heading

static func japanese() -> Font:
	if _japanese == null:
		_japanese = _font_file(JAPANESE_PATH)
		if _japanese == null: _japanese = fallback()
		else: _japanese.fallbacks = [fallback()]
	return _japanese

static func reading() -> Font:
	if _reading == null:
		_reading = _font_file(READING_PATH)
		if _reading == null: _reading = fallback()
		else: _reading.fallbacks = [fallback()]
	return _reading

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
