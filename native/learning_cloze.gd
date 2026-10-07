extends RefCounted
## A question is one verified source span; authored words and SRS IDs stay intact.
const BLANK := "＿＿"
const KANA_ALIASES := {
	"子供":"子ども", "友達":"友だち", "分かる":"わかる", "気づく":"気付く",
	"結び付ける":"結びつける", "取り付ける":"取りつける", "出来る":"できる",
	"ください":"下さい", "おはよう":"お早う"
}
const NATIVE_COUNTS := {"一":["一つ","ひとつ"],"二":["二つ","ふたつ"],"三":["三つ","みっつ"],"四":["四つ","よっつ"],"五":["五つ","いつつ"],"六":["六つ","むっつ"],"七":["七つ","ななつ"],"八":["八つ","やっつ"],"九":["九つ","ここのつ"]}
const GODAN := {
	"う":["い","わ","って","った"], "く":["き","か","いて","いた"],
	"ぐ":["ぎ","が","いで","いだ"], "す":["し","さ","して","した"],
	"つ":["ち","た","って","った"], "ぬ":["に","な","んで","んだ"],
	"ぶ":["び","ば","んで","んだ"], "む":["み","ま","んで","んだ"],
	"る":["り","ら","って","った"]
}
const PHONETIC_KEYS := ["romaji","romanization","readingKo","koReading","koreanReading","pronunciationKo","koreanPronunciation","phoneticKo","ipa"]

static func build(source: Dictionary, word: Dictionary) -> Dictionary:
	var jp: String = str(source.get("jp",""))
	var pieces: Array = source.get("parts",[])
	if jp.is_empty() or str(word.get("jp","")).is_empty():
		return {"valid":false,"error":"missing-source-or-word"}
	if pieces.is_empty(): pieces = [{"text":jp,"reading":str(source.get("reading",""))}]
	var joined: String = ""
	for part in pieces: joined += str(part.get("text",""))
	if joined!=jp: return {"valid":false,"error":"parts-do-not-match-source"}
	var span: Dictionary = find_span(source,word)
	if span.is_empty(): return {"valid":false,"error":"target-not-in-source"}
	var start: int = int(span.start)
	var finish: int = start+int(span.length)
	var masked_parts: Array = []
	var answer_parts: Array = []
	var offset: int = 0
	var inserted: bool = false
	for original in pieces:
		var text: String = str(original.get("text",""))
		var end: int = offset+text.length()
		if end<=start or offset>=finish:
			masked_parts.append(original.duplicate(true))
		else:
			var a: int = maxi(0,start-offset)
			var b: int = mini(text.length(),finish-offset)
			var fragments: Dictionary = _split_part(original,a,b,str(span.get("reading","")))
			if not bool(fragments.valid): return {"valid":false,"error":"unverified-partial-reading"}
			if not str(fragments.before.text).is_empty(): masked_parts.append(fragments.before)
			if not inserted:
				masked_parts.append({"text":BLANK})
				inserted = true
			answer_parts.append(fragments.answer)
			if not str(fragments.after.text).is_empty(): masked_parts.append(fragments.after)
		offset = end
	var question: Dictionary = source.duplicate(true)
	question.jp = jp.substr(0,start)+BLANK+jp.substr(finish)
	question.parts = masked_parts
	question.reading = _reading(masked_parts)
	question.erase("targetSpan")
	for key in PHONETIC_KEYS: question.erase(key)
	for part in question.parts:
		for key in PHONETIC_KEYS: part.erase(key)
	var answer_item: Dictionary = {"jp":jp.substr(start,int(span.length)),"reading":_reading(answer_parts),"parts":answer_parts,"ko":str(word.get("ko",""))}
	var cloze: Dictionary = span.duplicate(true)
	cloze["sourceJP"] = jp
	cloze["answerText"] = answer_item.jp
	cloze["answerReading"] = answer_item.reading
	cloze["answerItem"] = answer_item
	cloze["wordId"] = str(word.get("id",""))
	return {"valid":true,"questionItem":question,"revealItem":source.duplicate(true),"cloze":cloze}

static func find_span(source: Dictionary, word: Dictionary) -> Dictionary:
	var jp: String = str(source.get("jp",""))
	var authored: Variant = source.get("targetSpan")
	if authored is Dictionary:
		var text: String = str(authored.get("text",""))
		var start: int = int(authored.get("start",jp.find(text)))
		var length: int = int(authored.get("length",text.length()))
		var matches_id: bool = not authored.has("wordId") or str(authored.wordId)==str(word.get("id",""))
		if matches_id and not text.is_empty() and start>=0 and length==text.length() and jp.substr(start,length)==text:
			var result: Dictionary = {}
			for form in forms_for(word):
				if str(form.text)==text: result = form.duplicate(true);break
			if result.is_empty():
				var unit: String = str(word.get("jp",""))
				var prefix: String = text.trim_suffix(unit) if text.ends_with(unit) else ""
				var numeric: bool = not prefix.is_empty() and unit in ["分","秒","週","年","月","日","時","人","個","枚","本"]
				for character in prefix:
					if not character in "一二三四五六七八九十百千万〇零0123456789": numeric = false
				var declared_alias: bool = str(authored.get("wordId",""))==str(word.get("id","")) and not str(word.get("id","")).is_empty() and str(authored.get("relation","")) in ["synonym","honorific"]
				if not numeric and not declared_alias: return {}
				result = {"mode":"authored","suffix":""}
			result.merge({"start":start,"length":length,"text":text,"reading":str(authored.get("reading",result.get("reading",""))),"method":"authored"},true)
			return result
		# Invalid explicit metadata must never silently hide a different word.
		return {}
	var forms: Array = forms_for(word)
	# Dictionary spelling first; for an inflection, hide the complete source form.
	for form in forms:
		var text: String = str(form.text)
		var start: int = jp.find(text)
		while start>=0:
			if _word_boundary(jp,start,text,source.get("parts",[])):
				var result: Dictionary = form.duplicate(true)
				result["start"] = start
				result["length"] = text.length()
				return result
			start = jp.find(text,start+1)
	return {}

static func _word_boundary(source: String, start: int, text: String, parts: Array) -> bool:
	# A short kanji noun inside another compound is not proof of the same word.
	var boundaries: Array = [0]
	var offset: int = 0
	for part in parts:
		offset += str(part.get("text","")).length()
		boundaries.append(offset)
	var end: int = start+text.length()
	var counter: bool = text in ["分","秒","週","年","月","日","時","人","個","枚","本"] and start>0 and source.substr(start-1,1) in "一二三四五六七八九十百千万〇零0123456789"
	if _kanji(text.unicode_at(0)) and start>0 and _kanji(source.unicode_at(start-1)) and not start in boundaries and not counter: return false
	if _kanji(text.unicode_at(text.length()-1)) and end<source.length() and _kanji(source.unicode_at(end)) and not end in boundaries and not counter: return false
	return true

static func _kanji(code: int) -> bool:
	return (code>=0x3400 and code<=0x9fff) or (code>=0xf900 and code<=0xfaff)

static func forms_for(word: Dictionary) -> Array:
	var jp: String = str(word.get("jp",""))
	var reading: String = str(word.get("reading",jp))
	var values: Array = [{"text":jp,"reading":reading,"method":"exact","mode":"dictionary","suffix":""}]
	if NATIVE_COUNTS.has(jp): _form(values,NATIVE_COUNTS[jp][0],NATIVE_COUNTS[jp][1],"spelling","counter","つ")
	if jp=="年": _form(values,"今年","ことし","spelling","counter","今年")
	var spellings: Array = [jp]
	if KANA_ALIASES.has(jp): spellings.append(KANA_ALIASES[jp])
	for original in KANA_ALIASES:
		if str(KANA_ALIASES[original])==jp: spellings.append(original)
	for spelling in spellings:
		if spelling!=jp: _form(values,spelling,reading,"spelling","dictionary","")
		if spelling.ends_with("する"):
			var base: String = spelling.trim_suffix("する")
			var kana: String = reading.trim_suffix("する")
			for suffix in ["します","しました","しませんでした","しません","しています","していました","している","していた","して","した","しない","しなかった","すれば","しよう","される","させる"]:
				_form(values,base+suffix,kana+suffix,"inflection","suru",suffix)
			_form(values,base,kana,"nominal","suru","")
		elif spelling.ends_with("来る"):
			var base: String = spelling.trim_suffix("来る")
			var kana: String = reading.trim_suffix("くる")
			for row in [["来ます","きます"],["来ました","きました"],["来ません","きません"],["来て","きて"],["来た","きた"],["来ない","こない"],["来なかった","こなかった"],["来れば","くれば"]]:
				_form(values,base+row[0],kana+row[1],"inflection","kuru",str(row[0]))
		elif not spelling.is_empty() and GODAN.has(spelling.right(1)):
			var ending: String = spelling.right(1)
			var base: String = spelling.left(-1)
			var kana: String = reading.left(-1)
			var row: Array = GODAN[ending]
			for suffix in [str(row[0])+"ます",str(row[0])+"ました",str(row[0])+"ませんでした",str(row[0])+"ません",str(row[1])+"ない",str(row[1])+"なかった",str(row[1])+"ず",str(row[2]),str(row[3])]:
				_form(values,base+suffix,kana+suffix,"inflection","godan",suffix)
			if spelling.ends_with("行く"):
				for suffix in ["って","った"]: _form(values,base+suffix,kana+suffix,"inflection","godan",suffix)
			var te: String = "って" if spelling.ends_with("行く") else str(row[2])
			for suffix in [te+"います",te+"いました",te+"いる",te+"いた"]: _form(values,base+suffix,kana+suffix,"inflection","godan",suffix)
			if spelling in ["いらっしゃる","おっしゃる","なさる","くださる","ござる"]:
				for suffix in ["います","いました","いません"]: _form(values,base+suffix,kana+suffix,"inflection","honorific",suffix)
			if ending=="る":
				for suffix in ["ます","ました","ませんでした","ません","ています","ていました","ている","ていた","て","た","ない","なかった","れば","よう","られる","させる"]:
					_form(values,base+suffix,kana+suffix,"inflection","ichidan",suffix)
		elif spelling.ends_with("い"):
			for suffix in ["かった","くない","くなかった","く","ければ"]:
				_form(values,spelling.left(-1)+suffix,reading.left(-1)+suffix,"inflection","adjective",suffix)
	# Longer polite/negative forms precede shorter forms with the same root.
	var exact: Array = []
	var derived: Array = []
	for value in values:
		(exact if str(value.method) in ["exact","spelling"] else derived).append(value)
	derived.sort_custom(func(a: Dictionary,b: Dictionary): return str(a.text).length()>str(b.text).length())
	exact.append_array(derived)
	return exact

static func _form(values: Array, text: String, reading: String, method: String, mode: String, suffix: String) -> void:
	if text.is_empty(): return
	for value in values:
		if str(value.text)==text: return
	values.append({"text":text,"reading":reading,"method":method,"mode":mode,"suffix":suffix})

static func option(word: Dictionary, cloze: Dictionary, correct: bool = false) -> Dictionary:
	var item: Dictionary
	if correct:
		item = cloze.answerItem.duplicate(true)
	else:
		item = {"jp":str(word.get("jp","")),"reading":str(word.get("reading","")),"ko":str(word.get("ko","")),"parts":word.get("parts",[]).duplicate(true)}
		# Inferring a verb class from its final kana can invent forms such as 走ます.
		# Reuse a parallel form only when this candidate's own source proves it.
		for key in ["example","transferExample"]:
			var source: Variant = word.get(key)
			if not source is Dictionary: continue
			var span: Dictionary = find_span(source,word)
			if str(span.get("mode",""))!=str(cloze.get("mode","dictionary")) or str(span.get("suffix",""))!=str(cloze.get("suffix","")): continue
			var verified: Dictionary = build(source,word)
			if bool(verified.get("valid",false)):
				item = verified.cloze.answerItem.duplicate(true)
				break
	return {"id":str(word.get("id","")),"label":str(item.jp)+" · "+str(word.get("ko","")),"item":item}

static func same_answer(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("jp",""))==str(b.get("jp","")): return true
	if str(KANA_ALIASES.get(str(a.get("jp","")),""))==str(b.get("jp","")) and not str(b.get("jp","")).is_empty(): return true
	if str(KANA_ALIASES.get(str(b.get("jp","")),""))==str(a.get("jp","")) and not str(a.get("jp","")).is_empty(): return true
	var meanings: Array = _meanings(str(a.get("ko","")))
	for value in _meanings(str(b.get("ko",""))):
		if value in meanings: return true
	return false

static func _meanings(value: String) -> Array:
	var result: Array = []
	var clean: String = value.replace("/","·").replace(",","·").replace(" ","")
	for entry in clean.split("·",false):
		var term: String = entry.get_slice("(",0).get_slice("（",0)
		if not term.is_empty(): result.append(term)
	return result

static func _reading(parts: Array) -> String:
	var value: String = ""
	for part in parts:
		var kana: String = str(part.get("reading",""))
		value += str(part.get("text","")) if kana.is_empty() else kana
	return value

static func _split_part(part: Dictionary, a: int, b: int, known_reading: String) -> Dictionary:
	var text: String = str(part.get("text",""))
	var reading: String = str(part.get("reading",""))
	var before: String = text.substr(0,a)
	var answer: String = text.substr(a,b-a)
	var after: String = text.substr(b)
	var before_reading: String = ""
	var answer_reading: String = ""
	var after_reading: String = ""
	if not reading.is_empty() and reading!=text:
		if a==0 and b==text.length(): answer_reading = reading
		else:
			# Split only when the authored reading confirms the same source offset.
			var read_start: int = reading.find(known_reading) if not known_reading.is_empty() else -1
			if read_start<0 or (before.is_empty() and read_start!=0) or (after.is_empty() and read_start+known_reading.length()!=reading.length()):
				return {"valid":false}
			before_reading = reading.substr(0,read_start)
			answer_reading = known_reading
			after_reading = reading.substr(read_start+known_reading.length())
	return {"valid":true,"before":{"text":before,"reading":before_reading},"answer":{"text":answer,"reading":answer_reading},"after":{"text":after,"reading":after_reading}}
