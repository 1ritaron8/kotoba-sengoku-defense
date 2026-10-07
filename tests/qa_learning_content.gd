extends SceneTree
## Content contract and observable map-space checks. This is not a claim that
## automated structural checks replace native-speaker pedagogical review.
var checks: int = 0
var failures: Array = []
var totals: Dictionary = {"words":0,"expressions":0,"transferExamples":0,"stages":0,"missions":0,"linkedMissions":0}
var min_target_spacing: float = 1.0
var word_index: Dictionary = {}
var word_order: Dictionary = {}
var last_word_by_lesson: Dictionary = {}
var lesson_by_id: Dictionary = {}
var han: RegEx = RegEx.new()
var hangul: RegEx = RegEx.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("LEARNING CONTENT QA " + message)

func read_json(path: String) -> Variant:
	check(FileAccess.file_exists(path), "resource exists: " + path)
	var parser := JSON.new()
	var result: Error = parser.parse(FileAccess.get_file_as_string(path))
	check(result==OK, "valid JSON: " + path)
	return parser.data

func hiragana(value: String) -> String:
	var result: String = ""
	for i in value.length():
		var code: int = value.unicode_at(i)
		result += String.chr(code-0x60 if code>=0x30a1 and code<=0x30f6 else code)
	return result

func check_text(value: Dictionary, label: String) -> void:
	for key in ["jp","reading","ko"]:
		check(value.has(key) and value.get(key) is String and not String(value.get(key," ")).strip_edges().is_empty(), label+" contains "+key)
	check(hangul.search(String(value.get("ko","")))!=null,label+" Korean meaning")
	check(han.search(String(value.get("reading","")))==null,label+" kana reading")
	check(value.get("parts") is Array and not value.get("parts",[]).is_empty(),label+" ruby segments")
	var spelling: String = ""
	var reading: String = ""
	for part in value.get("parts",[]):
		check(part is Dictionary and part.get("text") is String,label+" ruby part shape")
		var segment: String = String(part.get("text",""))
		check(han.search(segment)==null or not String(part.get("reading","")).is_empty(),label+" every kanji segment annotated")
		spelling += segment
		reading += String(part.get("reading",hiragana(segment)))
	check(spelling==String(value.get("jp","")),label+" ruby spelling reconstruction")
	check(reading==String(value.get("reading","")),label+" ruby reading reconstruction")
	check(not spelling.contains("{") and not spelling.contains("@"),label+" no source placeholders")

func position(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x",-1)),float(value.get("y",-1)))

func run() -> void:
	han.compile("[\\x{3400}-\\x{4dbf}\\x{4e00}-\\x{9fff}々〆]")
	hangul.compile("[가-힣]")
	var curriculum: Dictionary = read_json("res://native/curriculum.json")
	var maps: Array = read_json("res://native/maps.json")
	var plans: Dictionary = read_json("res://native/learning_plans.json")
	var spellings: Dictionary = {}
	var transfers: Dictionary = {}
	var expected_sizes: Dictionary = {"basic":15,"beginner":20,"intermediate":25,"advanced":30}
	for tier in expected_sizes:
		var lessons: Array = curriculum.get(tier,[])
		check(lessons.size()==10,tier+" has ten lessons")
		for lesson in lessons:
			var lesson_id: String = lesson["id"]
			check(not lesson_by_id.has(lesson_id),"unique lesson "+lesson_id)
			lesson_by_id[lesson_id] = {"tier":tier,"lesson":lesson}
			var words: Array = lesson.get("newWords",[])
			check(words.size()==expected_sizes[tier],lesson_id+" new-word count")
			for word in words:
				var word_id: String = word["id"]
				check(not word_index.has(word_id),"unique word ID "+word_id)
				check(not spellings.has(word["jp"]),"unique spelling "+word_id)
				word_index[word_id] = word
				word_order[word_id] = totals["words"]
				spellings[word["jp"]] = true
				totals["words"] += 1
				check_text(word,word_id)
				check(word.get("example") is Dictionary,word_id+" first example")
				check_text(word.get("example",{}),word_id+" example")
				check(word.get("transferExample") is Dictionary,word_id+" second context")
				var transfer: Dictionary = word.get("transferExample",{})
				check_text(transfer,word_id+" transfer")
				check(transfer.get("jp","")!=word["example"]["jp"],word_id+" distinct context sentence")
				check(not transfers.has(transfer.get("jp","")),word_id+" unique transfer sentence")
				transfers[transfer.get("jp","")] = true
				totals["transferExamples"] += 1
			last_word_by_lesson[lesson_id] = totals["words"]-1
			for review_id in lesson.get("reviewIds",[]):
				check(word_index.has(review_id),lesson_id+" review refers to introduced word")
				check(not words.any(func(w): return w["id"]==review_id),lesson_id+" review separate from new list")
			check(lesson.get("expressions",[]).size()==2,lesson_id+" two original expressions")
			for expression in lesson.get("expressions",[]):
				check_text(expression,lesson_id+" expression")
				totals["expressions"] += 1
	check(totals["words"]==900,"900 original words remain")
	check(totals["expressions"]==80,"80 original expressions remain")
	check(plans.get("version")==1,"learning plan version")
	var stages: Dictionary = plans.get("stages",{})
	check(stages.size()==40 and maps.size()==40,"forty plans match forty maps")
	var goals: Dictionary = {}
	var mission_ids: Dictionary = {}
	var reports: Dictionary = {}
	var destinations: Dictionary = {1:{},3:{},6:{}}
	var advanced_contrast_count: int = 0
	for map in maps:
		var map_id: String = map["id"]
		check(stages.has(map_id),"plan exists "+map_id)
		var stage: Dictionary = stages.get(map_id,{})
		var lesson_id: String = stage.get("lessonId","")
		check(lesson_by_id.has(lesson_id),map_id+" existing lesson")
		check(stage.get("tier")==map["tier"] and lesson_by_id.get(lesson_id,{}).get("tier")==map["tier"],map_id+" tier agrees")
		var goal: String = stage.get("goalKo","")
		check(goal.length()>20 and hangul.search(goal)!=null,map_id+" useful learning goal")
		check(not goals.has(goal),map_id+" distinct learning goal")
		goals[goal] = true
		check(stage.get("grammar",[]).size()>=2,map_id+" grammar progression")
		for grammar in stage.get("grammar",[]):
			check(not grammar.get("jp","").is_empty() and hangul.search(grammar.get("ko",""))!=null,map_id+" bilingual grammar")
		var missions: Array = stage.get("missions",[])
		check(missions.size()==3,map_id+" three situations")
		var waves: Array = []
		for mission in missions:
			var mid: String = mission.get("id","")
			check(not mid.is_empty() and not mission_ids.has(mid),map_id+" unique expression item "+mid)
			mission_ids[mid] = true
			var wave: int = int(mission.get("wave",0))
			waves.append(wave)
			check(wave<map["totalWaves"],mid+" mission before final wave")
			check_text(mission.get("report",{}),mid+" report")
			var report: String = mission["report"]["jp"]
			check(not reports.has(report),mid+" unique situational report")
			reports[report] = true
			check(not report.contains("を選びましたが") and not report.contains("次の報告を聞いた後"),mid+" no false player action or unevaluated future event")
			var targets: Array = mission.get("targets",[])
			check(targets.size()>=2 and targets.size()<=3,mid+" two or three visible destinations")
			var target_ids: Dictionary = {}
			var answer: Dictionary = {}
			var answer_index: int = -1
			for i in targets.size():
				var target: Dictionary = targets[i]
				check(not target_ids.has(target.get("id","")),mid+" unique target")
				target_ids[target.get("id","")] = true
				check_text(target.get("label",{}),mid+" landmark label")
				var point: Vector2 = position(target.get("position",{}))
				check(point.x>=0.1 and point.x<=0.9 and point.y>=0.1 and point.y<=0.9,mid+" target label stays inside map")
				check(map["buildZones"].any(func(zone): return position(zone).distance_to(point)<0.00001),mid+" target grounded in actual build zone")
				if target["id"]==mission.get("answerId",""):
					answer = target
					answer_index = i
				for j in range(i+1,targets.size()):
					var spacing: float = point.distance_to(position(targets[j]["position"]))
					min_target_spacing = minf(min_target_spacing,spacing)
					check(spacing>=0.22,mid+" labels have map-space separation")
			check(not answer.is_empty() and answer_index>=0,mid+" exactly one correct destination")
			if not answer.is_empty():
				check(report.contains(answer["label"]["jp"]),mid+" request names correct destination")
				if stage.get("tier")=="advanced":
					var last_destination: String = ""
					var last_mention: int = -1
					for target in targets:
						var mention: int = report.rfind(target["label"]["jp"])
						if mention>last_mention:
							last_mention = mention
							last_destination = target["id"]
					if last_destination!=answer["id"]: advanced_contrast_count+=1
				var action: Dictionary = mission.get("action",{})
				check(action.get("kind")=="support",mid+" support effect kind")
				check(position(action.get("position",{})).distance_to(position(answer["position"]))<0.00001,mid+" effect at selected correct location")
				destinations[wave][answer_index] = int(destinations[wave].get(answer_index,0))+1
			var item_ids: Array = mission.get("itemIds",[])
			check(item_ids.size()<=1,mid+" one focused word maximum")
			for word_id in item_ids:
				check(word_index.has(word_id),mid+" existing focus vocabulary")
				check(word_order.get(word_id,9999)<=last_word_by_lesson.get(lesson_id,-1),mid+" no future word mastery credit")
			if not item_ids.is_empty(): totals["linkedMissions"] += 1
			check(hangul.search(mission.get("successKo",""))!=null,mid+" Korean feedback")
			totals["missions"] += 1
		check(waves==[1,3,6],map_id+" staged request timing")
		totals["stages"] += 1
	for wave in destinations:
		check(destinations[wave].size()==3,"wave "+str(wave)+" is not solved by one fixed destination")
	check(totals["missions"]==120,"120 new scenario expression items")
	check(advanced_contrast_count>=10,"advanced reports require interpreting contrast beyond last-place spotting")
	var forest: Array = stages.get("basic-forest",{}).get("missions",[])
	if forest.size()==3:
		for entry in forest:
			var focus: String = word_index[entry["itemIds"][0]]["jp"]
			check(focus in ["森","川","山"] and entry["report"]["jp"].contains(focus),"first forest natural-word comprehension")
	var result: Dictionary = {"checks":checks,"failures":failures,"totals":totals,"minimumTargetSeparation":min_target_spacing,"waveDestinationCounts":destinations,"advancedContrastReports":advanced_contrast_count,"resourceRoot":ProjectSettings.globalize_path("res://"),"limits":"Structure, ruby reconstruction and map coordinates checked; semantic naturalness reviewed separately."}
	var path: String = "res://tests/qa_learning_content.json"
	if OS.get_cmdline_user_args().has("--packed"): path="user://qa_learning_content.json"
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	print("LEARNING_CONTENT_QA "+JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
