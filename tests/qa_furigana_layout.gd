extends SceneTree

const RubyText = preload("res://native/ruby_label.gd")
const Fonts = preload("res://native/game_fonts.gd")
var checks: int = 0
var failures: Array[String] = []
var cases: int = 0
var face: Font
var label: Control
var largest_height: float = 0

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size()<12:
			push_error("FURIGANA_LAYOUT "+note)

func inspect(word: Dictionary, width: float, point_size: int, wrap: bool, meaning: bool, note: String) -> void:
	label.wrap_japanese = wrap
	label.size.x = width
	label.set_word(word,point_size,meaning)
	var layout: Dictionary = label.get_text_layout()
	label.size.y = float(layout.height)
	var bounds: Rect2 = Rect2(Vector2.ZERO,label.size)
	var body: String = ""
	var reading: String = ""
	var expected_reading: String = ""
	var parts: Array = word.get("parts",[])
	if parts.is_empty():
		if str(word.get("reading",""))!=str(word.get("jp","")):
			expected_reading = str(word.get("reading",""))
	else:
		for part in parts:
			if str(part.get("reading",""))!=str(part.get("text","")):
				expected_reading += str(part.get("reading",""))
	for run in layout.runs:
		check(bounds.grow(.1).encloses(run.bounds),note+": complete glyph bounds fit")
		var run_face: Font = Fonts.reading() if run.role=="reading" else Fonts.body() if run.role=="meaning" else face
		check(is_equal_approx(run.bounds.size.x,run_face.get_string_size(run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size)).x),note+": drawn text uses its full font advance")
		if run.role=="reading":
			check(int(run.size)>=16,note+": reading never shrinks below 16px")
			reading += str(run.text)
		elif run.role=="body":
			body += str(run.text)
	for first in range(layout.runs.size()):
		for second in range(first+1,layout.runs.size()):
			check(not layout.runs[first].bounds.intersects(layout.runs[second].bounds),note+": readings/body/translation do not overlap")
	check(body.replace(" ","").replace("\n","")==str(word.get("jp","")).replace(" ","").replace("\n",""),note+": Japanese text stays complete")
	# Two inherited misspellings have explicit display-only corrections.
	if str(word.get("jp",""))=="値段" and expected_reading=="のねだん": expected_reading="ねだん"
	if str(word.get("jp",""))=="品物" and expected_reading=="しなも": expected_reading="しなもの"
	check(reading.replace(" ","").replace("\n","")==expected_reading.replace(" ","").replace("\n",""),note+": reading stays complete")
	check(is_equal_approx(float(layout.height),label.custom_minimum_size.y),note+": parent receives the full measured height")
	largest_height = maxf(largest_height,float(layout.height))
	cases += 1

func _initialize() -> void:
	face = Fonts.japanese()
	label = RubyText.new()
	label.font = face
	var curriculum: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	var words: int = 0
	var sentences: int = 0
	for tier in curriculum:
		for lesson in curriculum[tier]:
			for word in lesson.newWords:
				inspect(word,230,36,false,true,str(word.id)+" battle")
				inspect(word,175,29,false,true,str(word.id)+" dictionary")
				words += 1
				for key in ["example","transferExample"]:
					inspect(word[key],784,24,false,true,str(word.id)+" "+key)
					inspect(word[key],640,36,true,true,str(word.id)+" wrapped "+key)
					sentences += 1
			for expression in lesson.get("expressions",[]):
				inspect(expression,784,24,false,true,str(lesson.id)+" expression")
	var plans: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	var reports: int = 0
	for stage in plans.stages.values():
		for mission in stage.get("missions",[]):
			inspect(mission.report,1184,36,true,false,str(mission.id)+" prompt")
			inspect(mission.report,1184,36,true,true,str(mission.id)+" result")
			inspect(mission.report,596,24,true,true,str(mission.id)+" field report")
			reports += 1
	var units: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	for unit in units.units:
		inspect({"jp":unit.jp,"reading":unit.reading,"parts":unit.get("parts",[]),"ko":unit.name},135,25,false,true,str(unit.id)+" roster")
		var forms: Array = [{"jp":unit.jp,"reading":unit.reading,"name":unit.name}]+unit.get("evolutions",[])
		for form in forms:
			var word: Dictionary = {"jp":form.jp,"reading":form.reading,"ko":form.name}
			inspect(word,208,26,false,true,str(unit.id)+" inspector")
			inspect(word,186,24,false,true,str(unit.id)+" evolution")
	inspect({"jp":"京働","parts":[{"text":"京","reading":"きょう"},{"text":"働","reading":"はたら"}],"ko":"긴 읽기"},110,36,true,true,"adjacent long readings")
	inspect({"jp":"熟練弓兵","reading":"じゅくれんきゅうへい","ko":"숙련 궁병"},110,24,false,true,"narrow compound")
	check(words==900 and sentences==1800 and reports==120,"All authored words/sentences/reports were checked")
	var report: Dictionary = {"checks":checks,"cases":cases,"failures":failures,"words":words,"sentences":sentences,"reports":reports,"largestHeight":largest_height,"minimumReadingPx":16}
	var output = FileAccess.open("user://qa_furigana_layout.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	label.free()
	print("FURIGANA_LAYOUT_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
