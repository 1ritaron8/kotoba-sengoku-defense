extends SceneTree
const Cloze = preload("res://native/learning_cloze.gd")
const Session = preload("res://native/learning_session.gd")
const Field = preload("res://native/learning_field.gd")
const Store = preload("res://native/progress.gd")
var checks: int = 0
var failures: Array = []
var evidence: Dictionary = {"words":0,"sentences":0,"missions":0,"methods":{},"geometry":[],"fairness":{}}
var curriculum: Dictionary
var plans: Dictionary
var lessons: Dictionary = {}
var store: RefCounted
var session: RefCounted
var field: Control
var context: String = ""

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(context+" · "+note)
		if failures.size()<=25: push_error("CLOZE "+context+" · "+note)

func verify(source: Dictionary, word: Dictionary, built: Dictionary) -> void:
	check(bool(built.get("valid",false)),"Source yields a verified vocabulary span: "+str(built.get("error","")))
	if not bool(built.get("valid",false)): return
	var span: Dictionary = built.cloze
	var start: int = int(span.start)
	var length: int = int(span.length)
	var jp: String = str(source.jp)
	check(start>=0 and length>0 and jp.substr(start,length)==str(span.answerText),"Masked answer is an exact nonempty substring of the authored source")
	check(str(built.questionItem.jp)==jp.substr(0,start)+Cloze.BLANK+jp.substr(start+length),"Only one answer span changes; every other source character remains")
	check(str(built.revealItem.jp)==jp and str(built.questionItem.ko)==str(source.ko) and not str(source.ko).is_empty(),"Reveal restores the source and Korean meaning remains a unique semantic cue")
	var joined: String = ""
	var blanks: int = 0
	for part in built.questionItem.parts:
		joined += str(part.text)
		if str(part.text)==Cloze.BLANK:
			blanks += 1
			check(str(part.get("reading","")).is_empty(),"Blank has no answer furigana")
		for key in Cloze.PHONETIC_KEYS: check(not part.has(key),"Rendered part contains no auxiliary answer phonetics")
	check(joined==str(built.questionItem.jp) and blanks==1,"Ruby pieces match the masked source with one blank")
	var offset: int = 0
	for part in source.get("parts",[]):
		var end: int = offset+str(part.text).length()
		if end<=start or offset>=start+length:
			check(part in built.questionItem.parts,"Every unaffected source Ruby part and reading remains intact")
		offset = end
	check(str(built.questionItem.reading).contains(Cloze.BLANK),"Sentence reading masks the same span")
	var method: String = str(span.method)
	evidence.methods[method] = int(evidence.methods.get(method,0))+1

func content_checks() -> void:
	for tier in ["basic","beginner","intermediate","advanced"]:
		for lesson in curriculum[tier]:
			session.begin_lesson(lesson,{"id":str(lesson.id),"stageNumber":40})
			for original in lesson.newWords:
				var word: Dictionary = session.word_index[str(original.id)]
				evidence.words += 1
				for kind in ["example","transferExample"]:
					context = str(word.id)+"/"+kind
					var source: Dictionary = word.get(kind,{})
					var pristine: Dictionary = source.duplicate(true)
					var built: Dictionary = Cloze.build(source,word)
					verify(source,word,built)
					check(source==pristine,"Mask extraction never mutates curriculum source")
					if not bool(built.get("valid",false)): continue
					var choices: Array = session._choices(word,built,"sentence")
					var ids: Dictionary = {}
					var labels: Dictionary = {}
					var correct: int = 0
					check(choices.size()>=2 and choices.size()<=(3 if tier=="basic" else 4),"Beginner-friendly vocabulary choices are bounded and usable")
					for choice in choices:
						ids[str(choice.id)] = true
						labels[str(choice.item.jp)] = true
						check(not str(choice.item.jp).is_empty() and str(choice.label).contains(str(choice.item.jp)),"Choice is a Japanese vocabulary item rather than the whole Korean sentence")
						if str(choice.id)==str(word.id):
							correct += 1
							check(str(choice.item.jp)==str(built.cloze.answerText),"Correct option reconstructs the exact dictionary/inflected source form")
						else:
							var candidate: Dictionary = session.word_index[str(choice.id)]
							check(not Cloze.same_answer(word,candidate),"Distractor has neither the same spelling nor an overlapping Korean meaning")
							var source_verified: bool = str(choice.item.jp)==str(candidate.jp)
							for key in ["example","transferExample"]:
								var candidate_source: Dictionary = candidate.get(key,{})
								if str(candidate_source.get("jp","")).contains(str(choice.item.jp)) and str(Cloze.find_span(candidate_source,candidate).get("text",""))==str(choice.item.jp): source_verified = true
							check(source_verified,"Inflected distractor is the candidate's actual source form, never a guessed verb class")
					check(correct==1 and ids.size()==choices.size() and labels.size()==choices.size(),"One correct internal answer and no duplicate equivalent options")
					evidence.sentences += 1
	check(evidence.words==900 and evidence.sentences==1800,"All900 words and both1800 authored sentences were verified")

func geometry(note: String) -> void:
	context = note
	var report: Rect2 = field.report_text.get_global_rect()
	var anchor: Rect2 = field.announcement_anchor.get_global_rect()
	check(Rect2(Vector2.ZERO,field.size).encloses(anchor) and anchor.size.y>=112 and anchor.size.x>=400,"Transparent112px announcement slot fits the context header")
	check(not anchor.intersects(field.report_heading.get_global_rect()) and not anchor.intersects(field.task_caption.get_global_rect()) and not anchor.intersects(report),"Guide slot covers neither heading, beginner instruction nor cloze sentence")
	check(field.report_text.meaning_visible and not str(field.report_text.word.ko).is_empty(),"Visible Korean cue makes the blank destination semantically unique")
	for run in field.report_text.get_text_layout().runs:
		check(Rect2(Vector2.ZERO,field.report_text.size).grow(1).encloses(run.bounds),"Every sentence/reading/cue glyph fits without clipping")
		check(int(run.size)>=16,"Remaining furigana and meaning retain readable type sizes")
	for button in field.target_buttons:
		var rect: Rect2 = button.get_global_rect()
		check(Rect2(Vector2.ZERO,field.size).encloses(rect) and rect.size.y>0,"Destination card fits the viewport")
		check(not rect.intersects(report) and not rect.intersects(anchor) and not rect.intersects(field.action_card.get_global_rect()),"No destination card overlaps guide, sentence or reward/action footer")
		var option: Control = button.get_node("DestinationWord")
		check(button.get_global_rect().encloses(option.get_global_rect()) and not option.get_global_rect().intersects(button.get_node("DestinationAction").get_global_rect()),"Japanese/furigana/Korean option fits above the deployment action label")

func mission_checks() -> void:
	for id in plans.stages:
		var plan: Dictionary = plans.stages[id]
		var lesson: Dictionary = lessons[str(plan.lessonId)]
		session.begin_lesson(lesson,{"id":id,"stageNumber":40})
		for mission in plan.missions:
			context = str(mission.id)
			var task: Dictionary = session._mission_task(mission,int(mission.wave))
			check(not task.is_empty(),"Every authored mission yields its exact masked destination")
			if task.is_empty(): continue
			var target: Dictionary = {}
			for candidate in mission.targets:
				if str(candidate.id)==str(mission.answerId): target = candidate.label
			verify(mission.report,target,{"valid":true,"questionItem":task.questionItem,"revealItem":task.revealItem,"cloze":task.cloze})
			check(task.answerId==mission.answerId and task.item.jp==mission.report.jp,"Context reward/action answer IDs and original item are unchanged")
			for dimensions in [Vector2(1280,800),Vector2(1440,900),Vector2(1920,1080)]:
				field.size = dimensions
				field.begin_choice(task.mission,false)
				field._arrange()
				check(str(field.report_text.word.jp)==str(task.questionItem.jp),"Initial context renders only the masked source")
				field.report_text.base_size = 24
				field._arrange()
				check(str(field.report_text.word.jp)==str(task.questionItem.jp),"Resize/font refresh cannot replace a pending blank with the answer")
				geometry(str(mission.id)+" "+str(dimensions)+" question")
				field.show_hint()
				check(field.report_text.word==task.revealItem,"Hint restores the identical source and other readings")
				field.size = dimensions+Vector2(1,1)
				field._arrange()
				check(field.report_text.word==task.revealItem,"Hint remains restored through another resize")
				geometry(str(mission.id)+" "+str(dimensions)+" hint")
				field.show_result(false,"오답입니다. 원문을 다시 읽어보십시오.","")
				check(field.report_text.word==task.revealItem,"Incorrect feedback also restores the exact source")
				await process_frame
				evidence.geometry.append({"missionId":mission.id,"size":dimensions,"report":field.report_text.get_global_rect(),"slot":field.announcement_anchor.get_global_rect(),"cardHeight":field.target_buttons[0].size.y})
			evidence.missions += 1
	check(evidence.missions==120,"All120 mission spans and three viewport layouts pass")

func edge_checks() -> void:
	context = "boundary / phonetics / explicit metadata"
	var word: Dictionary = {"id":"test","jp":"政策","reading":"せいさく","ko":"정책"}
	var source: Dictionary = {"jp":"政策決定です。","reading":"せいさくけっていです。","ko":"정책 결정입니다.","parts":[{"text":"政策決定","reading":"せいさくけってい"},{"text":"です。"}],"targetSpan":{"text":"政策","reading":"せいさく","start":0,"length":2,"wordId":"test"},"romaji":"seisaku kettei","readingKo":"세이사쿠"}
	var built: Dictionary = Cloze.build(source,word)
	check(bool(built.valid) and str(built.questionItem.parts[1].reading)=="けってい","Verified partial Ruby retains the unmasked compound reading")
	check(not built.questionItem.has("romaji") and not built.questionItem.has("readingKo"),"Answer romanization and Korean sound annotations never reach the masked item")
	var invalid: Dictionary = source.duplicate(true)
	invalid.targetSpan.start = 2
	check(not bool(Cloze.build(invalid,word).valid),"Incorrect authored offset is rejected without masking another word")
	invalid = source.duplicate(true)
	invalid.targetSpan.wordId = "foreign"
	check(not bool(Cloze.build(invalid,word).valid),"Foreign vocabulary metadata cannot override the target")
	invalid = source.duplicate(true)
	invalid.targetSpan = {"text":"決定","reading":"けってい","start":2,"length":2,"wordId":"test"}
	check(not bool(Cloze.build(invalid,word).valid),"Even matching vocabulary metadata cannot hide an unrelated source word")
	var absent: Dictionary = {"jp":"政治家です。","reading":"せいじかです。","ko":"정치인입니다.","parts":[{"text":"政治家","reading":"せいじか"},{"text":"です。"}]}
	check(not bool(Cloze.build(absent,word).valid),"Absent target never masks an unrelated source noun")
	check(not bool(Cloze.build({"jp":"目印です。","ko":"표식입니다.","parts":[{"text":"目印","reading":"めじるし"},{"text":"です。"}]},{"jp":"目","reading":"め","ko":"눈"}).valid),"Short kanji inside an unrelated compound is not a target word")
	for row in [["いらっしゃる","いらっしゃいます","いらっしゃいます"],["おっしゃる","おっしゃいました","おっしゃいました"],["来る","来ます","きます"],["行く","行って","いって"],["分かる","わかります","わかります"]]:
		var full: Dictionary = {"jp":row[1]+"。","reading":row[2]+"。","ko":"확인용 의미 단서","parts":[{"text":row[1],"reading":row[2]},{"text":"。"}]}
		var value: Dictionary = Cloze.build(full,{"jp":row[0],"reading":"くる" if row[0]=="来る" else "いく" if row[0]=="行く" else row[0],"ko":"확인"})
		check(bool(value.valid) and value.cloze.answerText==row[1],"Honorific/spelling/conjugated target remains the actual full source form "+str(row[0]))
	var seeing: Dictionary = {"id":"seeing","jp":"見る","reading":"みる","ko":"보다","parts":[{"text":"見","reading":"み"},{"text":"る"}],"example":{"jp":"見ます。","ko":"봅니다.","parts":[{"text":"見","reading":"み"},{"text":"ます。"}]}}
	var running: Dictionary = {"id":"running","jp":"走る","reading":"はしる","ko":"달리다","parts":[{"text":"走","reading":"はし"},{"text":"る"}],"example":{"jp":"走ります。","ko":"달립니다.","parts":[{"text":"走","reading":"はし"},{"text":"ります。"}]}}
	var eating: Dictionary = {"id":"eating","jp":"食べる","reading":"たべる","ko":"먹다","parts":[{"text":"食","reading":"た"},{"text":"べる"}],"example":{"jp":"食べます。","ko":"먹습니다.","parts":[{"text":"食","reading":"た"},{"text":"べます。"}]}}
	var seeing_blank: Dictionary = Cloze.build(seeing.example,seeing)
	var running_blank: Dictionary = Cloze.build(running.example,running)
	check(str(Cloze.option(running,seeing_blank.cloze).item.jp)=="走る","Ichidan question never invents a godan distractor such as 走ます")
	check(str(Cloze.option(seeing,running_blank.cloze).item.jp)=="見る","Godan question never invents an ichidan distractor such as 見ります")
	check(str(Cloze.option(eating,seeing_blank.cloze).item.jp)=="食べます","Candidate's own verified polite form remains available as a parallel distractor")

func fairness_checks() -> void:
	context = "new exposure / SRS interleaving / receipts"
	var sample: Dictionary = curriculum.basic[0]
	var local = Session.new()
	local.configure(store,curriculum,{})
	local.begin_lesson(sample,{"id":"basic-forest","stageNumber":1})
	check(local.next_task([],1,false).is_empty(),"No ordinary question introduces an unexposed word")
	var seen: Array = []
	for word in sample.newWords:
		seen.append(str(word.id))
		store.mark_exposure(str(word.id),"meaning","cloze-fairness")
	var before: Dictionary = store.data.army.duplicate(true)
	var sequence: Array = []
	var first_round: Dictionary = {}
	for index in range(45):
		var task: Dictionary = local.next_task(seen,index+1,false)
		check(not task.is_empty() and str(task.itemId) in seen,"Question remains within actually exposed words")
		if task.is_empty(): continue
		var count: int = int(local.issued_counts.get(str(task.itemId),0))
		var cached: Dictionary = local.next_task(seen,index+1,false)
		check(cached==task and int(local.issued_counts.get(str(task.itemId),0))==count,"Pending/resize reissue cannot inflate word issuance counts")
		sequence.append(task.itemId)
		if index<seen.size(): first_round[str(task.itemId)] = true
		var answer: String = str(task.answerId)
		if str(task.itemId)==str(seen[0]):
			for option in task.choices:
				if str(option.id)!=answer: answer = str(option.id);break
		var result: Dictionary = local.record(task,answer,false)
		check(bool(result.accepted) and not bool(local.record(task,answer,false).accepted),"Original durable learning receipt remains single-use")
	check(first_round.size()==seen.size(),"All15 newly exposed words are issued before any one word monopolizes practice")
	var failed_count: int = sequence.count(str(seen[0]))
	check(failed_count>=2 and failed_count<=16,"Repeated failure returns for spaced review while other vocabulary still circulates")
	check(store.data.army==before,"Question fairness and masked answers cannot alter permanent army funds")
	var with_mission = Session.new()
	with_mission.configure(store,curriculum,plans)
	with_mission.begin_lesson(sample,{"id":"basic-forest","stageNumber":1})
	var mission_task: Dictionary = with_mission.next_task(seen,1,false)
	check(str(mission_task.kind)=="context" and int(with_mission.issued_counts.get(str(mission_task.representativeItemId),0))==1,"Actual context representative counts toward the same vocabulary rotation")
	evidence.fairness = {"seen":seen.size(),"firstRound":first_round.size(),"failedWordIssued":failed_count,"sequence":sequence,"counts":local.issued_counts.duplicate(true)}

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/learning-cloze/"): push_error("Cloze QA refuses the player's profile");quit(2);return
	curriculum = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	plans = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	for tier in curriculum:
		for lesson in curriculum[tier]: lessons[str(lesson.id)] = lesson
	store = Store.new()
	store.save_path = "user://cloze-%d.json" % Time.get_ticks_usec()
	session = Session.new()
	session.configure(store,curriculum,plans)
	field = Field.new()
	field.font = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	root.add_child(field)
	field.set_process(false)
	await content_checks()
	await mission_checks()
	edge_checks()
	fairness_checks()
	field.queue_free()
	await process_frame
	var report: Dictionary = {"checks":checks,"failures":failures,"evidence":evidence,"scope":"All900 vocabulary entries/two1800 source sentences, all120 mission targets with source-substring masks and intact outside Ruby, exact Japanese inflected choices/semantic Korean cues, three viewport context geometry/resize/hint/result, honorific/alias/invalid metadata and no-unexposed-word/all-item rotation with real isolated durable SRS receipts. No GPU, campaign rewards or player profile writes."}
	var path: String = "user://qa_learning_cloze_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_learning_cloze_headless.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("LEARNING_CLOZE ",checks," checks / ",failures.size()," failures / ",evidence.sentences," sentences / ",evidence.missions," missions; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)
