extends RefCounted
## Display-only kanji alignment. Never changes lesson IDs, answers or gate scope.

const LOOKUP_PATH: String = "res://native/ruby_readings.json"
static var _lookup: Dictionary = {}
static var _ui_lookup: Dictionary = {}
static var _ui_initials: Dictionary = {}
static var _loaded: bool = false

static func _load_lookup() -> void:
	if _loaded: return
	_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOKUP_PATH))
	if data is Dictionary and data.get("segments") is Dictionary:
		_lookup = data.segments
		_ui_lookup = data.get("uiWords",{})
		for body in _ui_lookup:
			var first: String=str(body).left(1)
			if not _ui_initials.has(first): _ui_initials[first]=[]
			_ui_initials[first].append(str(body))

static func _is_kanji(code: int) -> bool:
	return code in [0x3005,0x303b] or (code>=0x3400 and code<=0x4dbf) or (code>=0x4e00 and code<=0x9fff) or (code>=0xf900 and code<=0xfaff) or (code>=0x20000 and code<=0x323af)

static func contains_kanji(text: String) -> bool:
	for index in range(text.length()):
		if _is_kanji(text.unicode_at(index)): return true
	return false

static func _has_kana(text: String) -> bool:
	for index in range(text.length()):
		var code: int=text.unicode_at(index)
		if code>=0x3040 and code<=0x30ff: return true
	return false

static func uncovered_kanji(parts: Array) -> Array:
	var missing: Array=[]
	for part in parts:
		var body: String=str(part.get("text",""))
		var reading: String=str(part.get("reading",""))
		if contains_kanji(body) and (not _has_kana(reading) or contains_kanji(reading)):
			missing.append(body)
	return missing

static func for_text(text: String, context_words: Array = []) -> Array:
	_load_lookup()
	var known: Dictionary=_ui_lookup.duplicate()
	var initials: Dictionary=_ui_initials.duplicate()
	var copied_initials: Dictionary={}
	for word in context_words:
		if not word is Dictionary: continue
		var body: String=str(word.get("jp",word.get("nameJP","")))
		var reading: String=str(word.get("reading",""))
		if not body.is_empty() and _has_kana(reading) and not contains_kanji(reading):
			known[body]=[{"text":body,"reading":reading}]
			var first: String=body.left(1)
			if not copied_initials.has(first):
				initials[first]=initials.get(first,[]).duplicate()
				copied_initials[first]=true
			if not initials[first].has(body): initials[first].append(body)
	var result: Array=[]
	var plain: String=""
	var offset: int=0
	while offset<text.length():
		var matched: String=""
		for key in initials.get(text.substr(offset,1),[]):
			var candidate: String=str(key)
			if candidate.length()==1:
				# A named single-character word is never a fallback inside a
				# different compound (for example music 戦 vs. 戦闘).
				if offset>0 and _is_kanji(text.unicode_at(offset-1)): continue
				if offset+1<text.length() and _is_kanji(text.unicode_at(offset+1)): continue
			if candidate.length()>matched.length() and text.substr(offset,candidate.length())==candidate: matched=candidate
		if matched.is_empty():
			plain+=text.substr(offset,1)
			offset+=1
			continue
		if not plain.is_empty(): result.append({"text":plain,"reading":""}); plain=""
		for piece in known[matched]: result.append(piece.duplicate())
		offset+=matched.length()
	if not plain.is_empty(): result.append({"text":plain,"reading":""})
	return result

static func word_for_text(text: String, context_words: Array = []) -> Dictionary:
	return {"jp":text,"parts":for_text(text,context_words)}

static func _all_kanji(text: String) -> bool:
	if text.is_empty(): return false
	for index in range(text.length()):
		var code: int = text.unicode_at(index)
		if not _is_kanji(code):
			return false
	return true

static func _append_segments(result: Array, piece: Dictionary) -> void:
	var text: String = str(piece.get("text",""))
	var reading: String = str(piece.get("reading",""))
	var key: String = text+"\t"+reading
	if _lookup.has(key):
		for span in _lookup[key]: result.append(span.duplicate())
	elif reading.is_empty() and _ui_lookup.has(text):
		for span in _ui_lookup[text]: result.append(span.duplicate())
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
	elif not uncovered_kanji(source).is_empty():
		# A verified authored whole-word reading covers incomplete subdivisions.
		# No reading is inferred from a character's unrelated dictionary readings.
		var text: String=str(word.get("jp",""))
		var reading: String=str(word.get("reading",""))
		if contains_kanji(text) and _has_kana(reading) and not contains_kanji(reading):
			source=[{"text":text,"reading":reading}]
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
