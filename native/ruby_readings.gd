extends RefCounted
## Display-only kanji alignment. Never changes lesson IDs, answers or gate scope.

const LOOKUP_PATH: String = "res://native/ruby_readings.json"
static var _lookup: Dictionary = {}
static var _loaded: bool = false

static func _load_lookup() -> void:
	if _loaded: return
	_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOKUP_PATH))
	if data is Dictionary and data.get("segments") is Dictionary:
		_lookup = data.segments

static func _all_kanji(text: String) -> bool:
	if text.is_empty(): return false
	for index in range(text.length()):
		var code: int = text.unicode_at(index)
		if not (code==0x3005 or (code>=0x3400 and code<0x4dc0) or (code>=0x4e00 and code<0xa000)):
			return false
	return true

static func _append_segments(result: Array, piece: Dictionary) -> void:
	var text: String = str(piece.get("text",""))
	var reading: String = str(piece.get("reading",""))
	var key: String = text+"\t"+reading
	if _lookup.has(key):
		for span in _lookup[key]: result.append(span.duplicate())
	else:
		result.append({"text":text,"reading":reading})

static func _append_run(result: Array, run: Array) -> void:
	if run.is_empty(): return
	var text: String = ""
	var reading: String = ""
	for piece in run:
		text += str(piece.text)
		reading += str(piece.reading)
	var key: String = text+"\t"+reading
	if _lookup.has(key):
		_append_segments(result,{"text":text,"reading":reading})
	else:
		# An unknown joined phrase must retain the author's known boundaries.
		# Do not erase independent character readings just because a whole run
		# has no verified compound entry.
		for piece in run: _append_segments(result,piece)

static func for_word(word: Dictionary) -> Array:
	_load_lookup()
	var source: Array = word.get("parts",[])
	if source.is_empty():
		var text: String = str(word.get("jp",""))
		var reading: String = str(word.get("reading",""))
		source = [{"text":text,"reading":reading if reading!=text else ""}]
	# An authored compound may already have tentative character divisions.
	# Recombine only contiguous kanji; lookup restores verified boundaries.
	var result: Array = []
	var run: Array = []
	for item in source:
		var text: String = str(item.get("text",""))
		var reading: String = str(item.get("reading",""))
		if not reading.is_empty() and _all_kanji(text):
			run.append({"text":text,"reading":reading})
		else:
			_append_run(result,run)
			run.clear()
			_append_segments(result,{"text":text,"reading":reading})
	_append_run(result,run)
	return result
