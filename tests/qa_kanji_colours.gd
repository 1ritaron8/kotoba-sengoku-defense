extends SceneTree

const Ruby = preload("res://native/ruby_label.gd")
const Readings = preload("res://native/ruby_readings.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size()<15: push_error("KANJI_COLOURS "+note)

func verify_label(word: Dictionary, expected: Array) -> void:
	var label = Ruby.new()
	label.size = Vector2(750,240)
	label.set_word(word,36,false)
	var layout: Dictionary = label.get_text_layout()
	check(label.colour_reading_groups and not label.merge_adjacent_readings,"Global defaults keep individually coloured kanji")
	check(not label.show_reading_guides and layout.guides.is_empty(),"No separators or connecting guides")
	var ruby_runs: Array = []
	var body_runs: Array = []
	for run in layout.runs:
		if run.role=="reading": ruby_runs.append(run)
		elif run.role=="body": body_runs.append(run)
	check(ruby_runs.size()==expected.size(),"Every expected kanji has its own kana group: "+str(word.jp))
	for index in range(mini(expected.size(),ruby_runs.size())):
		check(ruby_runs[index].text==expected[index],"Accurate character reading: "+str(word.jp))
		check(ruby_runs[index].color==body_runs[index].color,"Kanji and its kana share the exact colour")
		if index>0:
			check(ruby_runs[index].color!=ruby_runs[index-1].color,"Adjacent kanji alternate colours")
		check(int(ruby_runs[index].size)>=20,"Kana remains legible")
		if index>0:
			check(absf(body_runs[index].bounds.position.x-body_runs[index-1].bounds.end.x)<.1,"Base kanji keep normal contiguous advances")
			check(ruby_runs[index].bounds.position.x>ruby_runs[index-1].bounds.end.x,"Adjacent kana have a measurable non-touching gap")
	label.free()

func verify_compact(word: Dictionary, width: float, points: int, spacing: float=0.0) -> void:
	var label=Ruby.new()
	label.size=Vector2(width,1000)
	label.wrap_japanese=true
	label.group_spacing=spacing
	var original: String=JSON.stringify(word)
	label.set_word(word,points,true)
	var layout: Dictionary=label.get_text_layout()
	check(JSON.stringify(word)==original,"Layout preserves source data")
	var bodies: Array=[]
	var readings: Array=[]
	for run in layout.runs:
		check(Rect2(Vector2.ZERO,Vector2(width,float(layout.height))).grow(.1).encloses(run.bounds),"Every compact layout run fits its widget: "+str(word.jp))
		if run.role=="body": bodies.append(run)
		if run.role=="reading": readings.append(run)
	var reproduced: String=""
	for index in range(bodies.size()):
		var run: Dictionary=bodies[index]
		reproduced+=run.text
		if index>0 and is_equal_approx(run.bounds.position.y,bodies[index-1].bounds.position.y):
			check(absf(run.bounds.position.x-bodies[index-1].bounds.end.x)<.1,"No artificial spacing in compact or wrapped Japanese")
	for index in range(readings.size()):
		check(int(readings[index].size)>=16,"Ruby remains at least 16 points")
		for next in range(index+1,readings.size()): check(not readings[index].bounds.grow(.01).intersects(readings[next].bounds),"Ruby groups never touch or overlap")
	check(reproduced==str(word.jp),"Wrapping preserves the complete Japanese spelling")
	check(float(layout.height)<=label.custom_minimum_size.y+.1,"Measured minimum height fits ruby and Korean meaning")
	if str(word.jp) in ["出陣","兵舎"]:
		var body_width: float=0.0
		for run in bodies: body_width+=run.bounds.size.x
		check(absf(body_width-label.font.get_string_size(str(word.jp),HORIZONTAL_ALIGNMENT_LEFT,-1,points).x)<.1,"Short menu word retains its native font width")
		check(absf((bodies[0].bounds.position.x+bodies[-1].bounds.end.x)*.5-width*.5)<.1,"Compact body is centred independently of ruby")
		check(absf((readings[0].bounds.position.x+readings[-1].bounds.end.x)*.5-width*.5)<.1,"Overhanging reading row stays centred above the whole word")
	label.free()

func _initialize() -> void:
	verify_label({"jp":"手加減","reading":"てかげん"},["て","か","げん"])
	verify_label({"jp":"鉄砲兵","reading":"てっぽうへい"},["てっ","ぽう","へい"])
	verify_label({"jp":"地面","reading":"じめん","parts":[{"text":"地面","reading":"じめん"}]},["じ","めん"])
	verify_compact({"jp":"出陣","reading":"しゅつじん","ko":"출진"},110,24,8)
	verify_compact({"jp":"兵舎","reading":"へいしゃ","ko":"병영"},110,24,6)
	verify_compact({"jp":"鉄砲兵","reading":"てっぽうへい","ko":"조총병"},110,30,8)
	verify_compact({"jp":"今日","reading":"きょう","ko":"오늘"},110,30,8)
	var unknown: Dictionary={"jp":"京働","parts":[{"text":"京","reading":"きょう"},{"text":"働","reading":"はたら"}]}
	var original: String=JSON.stringify(unknown)
	check(Readings.for_word(unknown)==unknown.parts,"An unknown joined phrase preserves authored character boundaries")
	check(JSON.stringify(unknown)==original,"Display preparation never mutates lesson data")
	var today: Array=Readings.for_word({"jp":"今日","reading":"きょう"})
	check(today.size()==1 and today[0].text=="今日" and today[0].reading=="きょう","Whole-word irregular readings never invent false kanji pronunciation")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/ruby_readings.json"))
	for key in data.segments:
		var compound: Array=key.split("\t")
		var body: String=""
		var reading: String=""
		for span in data.segments[key]:
			body+=str(span.text)
			reading+=str(span.reading)
			check(str(span.text).length()==1 or bool(span.get("wholeWordReading",false)),"Only identified whole-word readings retain multiple kanji")
		check(body==compound[0],"Verified alignment preserves the Japanese spelling")
		check(reading.replace(" ","")==str(data.displayCorrections.get(key,compound[1])).replace(" ",""),"Verified alignment preserves the complete kana")
	var story: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	for stage in story.stages:
		var spans: Array=Readings.for_word({"jp":stage.briefingJP,"reading":stage.briefingReading,"parts":stage.briefingParts})
		var body: String=""
		var pronunciation: String=""
		for span in spans:
			body+=str(span.text)
			pronunciation+=str(span.reading) if not str(span.get("reading","")).is_empty() else str(span.text)
		check(body==stage.briefingJP and pronunciation==stage.briefingReading,"Every briefing keeps accurate text and full spoken reading")
		verify_compact({"jp":stage.briefingJP,"reading":stage.briefingReading,"parts":stage.briefingParts,"ko":"보고 내용"},330,28,8)
	print("KANJI_COLOURS checks=",checks," failures=",failures.size()," entries=",data.segments.size())
	quit(0 if failures.is_empty() else 1)
