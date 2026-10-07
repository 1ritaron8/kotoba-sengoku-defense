extends RefCounted
## Lesson tasks select actual authored words and sentences; never unlocked future words.
const Cloze = preload("res://native/learning_cloze.gd")
var store: RefCounted
var words: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var word_index: Dictionary = {}
var lesson_numbers: Dictionary = {}
var plans: Dictionary = {}
var lesson: Dictionary = {}
var stage: Dictionary = {}
var pending: Dictionary = {}
var used_missions: Dictionary = {}
var session_id: String = ""
var task_counter: int = 0
var practice_counter: int = 0
var last_item_id: String = ""
var maximum_reached: int = 0
var sentence_turn: Dictionary = {}
var hinted_tasks: Dictionary = {}
var issued_counts: Dictionary = {}

func configure(progress_store: RefCounted, curriculum: Dictionary, learning_plans: Dictionary) -> void:
	store = progress_store
	plans = learning_plans
	word_index.clear()
	lesson_numbers.clear()
	var number: int = 0
	for tier in ["basic","beginner","intermediate","advanced"]:
		for entry in curriculum.get(tier,[]):
			number += 1
			lesson_numbers[str(entry.id)] = number
			for word in entry.get("newWords",[]):
				var value: Dictionary = word.duplicate(true)
				value["lessonNumber"] = number
				if not value.has("transferExample") and plans.get("transferExamples") is Dictionary and plans.transferExamples.get(str(word.id)) is Dictionary:
					value["transferExample"] = plans.transferExamples[str(word.id)].duplicate(true)
				word_index[str(word.id)] = value
	rng.randomize()

func begin_lesson(current_lesson: Dictionary, current_stage: Dictionary) -> void:
	lesson = current_lesson
	stage = current_stage
	words = []
	pending = {}
	used_missions = {}
	task_counter = 0
	practice_counter = 0
	last_item_id = ""
	sentence_turn = {}
	hinted_tasks = {}
	issued_counts = {}
	session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	maximum_reached = maxi(int(current_stage.get("stageNumber",0)),int(lesson_numbers.get(str(current_lesson.get("id","")),1)))
	for map_id in store.data.maps:
		maximum_reached = maxi(maximum_reached,int(store.stage_numbers.get(str(map_id),0)))
	var included: Dictionary = {}
	for original in current_lesson.get("newWords",[]):
		_add_word(str(original.id),included,original)
	# Authored reviewIds set the word-count budget, not a fixed personal queue.
	# Replaying a reached map must not introduce unseen words from other maps.
	var review_budget: int = current_lesson.get("reviewIds",[]).size()
	var current_number: int = int(lesson_numbers.get(str(current_lesson.get("id","")),current_stage.get("stageNumber",1)))
	var previous_ids: Array = []
	for id in word_index:
		if int(word_index[id].lessonNumber)<current_number and int(word_index[id].lessonNumber)<=maximum_reached and not included.has(id) and _previously_exposed(str(id)):
			previous_ids.append(id)
	for id in store.review_ids(previous_ids,review_budget):
		_add_word(str(id),included)

func _previously_exposed(id: String) -> bool:
	var historical: Dictionary = store.data.words.get(id,{})
	if int(historical.get("seen",0))>0: return true
	for skill in ["meaning","context","listening"]:
		var status: Dictionary = store.learning_status(id,skill)
		if int(status.exposures)>0 or int(status.correct)>0 or int(status.wrong)>0: return true
	return false

func _add_word(id: String, included: Dictionary, fallback: Dictionary = {}) -> void:
	if included.has(id): return
	var word: Dictionary = word_index.get(id,fallback)
	if word.is_empty(): return
	words.append(word.duplicate(true))
	included[id] = true

func next_task(seen_ids: Array, wave: int, voice_available: bool) -> Dictionary:
	if not pending.is_empty(): return pending.duplicate(true)
	var plan: Dictionary = plans.get("stages",{}).get(str(stage.get("id","")),{})
	for mission in plan.get("missions",[]):
		var mission_id: String = str(mission.get("id",""))
		if int(mission.get("wave",1))<=wave and not used_missions.has(mission_id):
			var built: Dictionary = _mission_task(mission,wave)
			if not built.is_empty():
				used_missions[mission_id] = true
				_count_issued(str(built.get("representativeItemId","")))
				pending = built
				return pending.duplicate(true)
	var candidates: Array = []
	for word in words:
		if str(word.id) in seen_ids: candidates.append(word)
	if candidates.is_empty():
		for word in words:
			if _previously_exposed(str(word.id)): candidates.append(word)
	if candidates.is_empty(): return {}
	var eligible: Array = []
	for word in candidates:
		if str(word.id)!=last_item_id or candidates.size()==1: eligible.append(str(word.id))
	if eligible.is_empty():
		for word in candidates: eligible.append(str(word.id))
	var chosen: String = _choose_word(eligible,practice_counter%2==0)
	var word: Dictionary = word_index.get(chosen,{})
	if word.is_empty():
		for candidate in candidates:
			if str(candidate.id)==chosen: word = candidate
	if word.is_empty(): return {}
	var kind: String = "meaning"
	var skill: String = "meaning"
	var item: Dictionary = word.duplicate(true)
	var context_id: String = "meaning:"+chosen
	var index: int = practice_counter%3
	if index==1 and _has_sentence(word):
		kind = "sentence"
		skill = "context"
		item = _sentence(word)
		context_id = str(item.get("contextId","example:"+chosen))
	elif index==2 and voice_available and not str(word.get("reading","")).is_empty():
		kind = "listening"
		skill = "listening"
		context_id = "listening:"+chosen
	elif index==2 and _has_sentence(word):
		kind = "sentence"
		skill = "context"
		item = _sentence(word)
		context_id = str(item.get("contextId","example:"+chosen))
	var source: Dictionary = item if kind=="sentence" else word.get("example",word)
	var blank: Dictionary = Cloze.build(source,word)
	if not bool(blank.valid):
		# A malformed transfer sentence must not mask a nearby unrelated word.
		blank = Cloze.build(word.get("example",word),word)
	if not bool(blank.valid): return {}
	var choices: Array = _choices(word,blank,kind)
	if choices.size()<2: return {}
	practice_counter += 1
	_count_issued(chosen)
	pending = {"id":_attempt_id(wave,chosen),"kind":kind,"item":item,"itemId":chosen,"skill":skill,"contextId":context_id,"choices":choices,"answerId":chosen,"questionItem":blank.questionItem,"revealItem":blank.revealItem,"cloze":blank.cloze,"promptKo":"빈칸에 들어갈 일본어를 고르십시오.","cueKo":str(blank.questionItem.get("ko","")),"showMeaning":true}
	return pending.duplicate(true)

func _count_issued(id: String) -> void:
	if not id.is_empty(): issued_counts[id] = int(issued_counts.get(id,0))+1

func _choose_word(ids: Array, review_turn: bool) -> String:
	if ids.is_empty(): return ""
	var ranked: Array = store.review_ids(ids,ids.size())
	if ranked.is_empty(): ranked = ids.duplicate()
	var least: int = 2147483647
	for id in ids: least = mini(least,int(issued_counts.get(str(id),0)))
	var priority: int = -1
	if review_turn and least>0:
		for id in ids: priority = maxi(priority,_priority(str(id)))
	var selected: Array = []
	var selected_count: int = 2147483647
	for id in ranked:
		if priority>=0 and _priority(str(id))!=priority: continue
		var count: int = int(issued_counts.get(str(id),0))
		if count<selected_count:
			selected.clear()
			selected_count = count
		if count==selected_count: selected.append(str(id))
	# All tied items remain eligible; a fixed first-four pool starved the rest.
	return str(selected[rng.randi_range(0,selected.size()-1)]) if not selected.is_empty() else str(ranked[0])

func _priority(id: String) -> int:
	var result: int = 0
	for skill in ["meaning","context","listening"]:
		var status: Dictionary = store.learning_status(id,skill)
		if status.status=="wrong": result = maxi(result,4)
		elif status.status=="hinted": result = maxi(result,3)
		elif status.due and int(status.correct)>0: result = maxi(result,2)
		elif int(status.exposures)>0 or int(status.correct)>0: result = maxi(result,1)
	return result

func _has_sentence(word: Dictionary) -> bool:
	return word.get("example") is Dictionary and not str(word.example.get("jp","")).is_empty() and not str(word.example.get("ko","")).is_empty()

func _sentence(word: Dictionary) -> Dictionary:
	var id: String = str(word.id)
	var example: Dictionary = word.example
	var alternate: Dictionary = word.get("transferExample",{})
	var has_alternate: bool = not str(alternate.get("jp","")).is_empty() and not str(alternate.get("ko","")).is_empty() and str(alternate.jp)!=str(example.jp)
	var use_alternate: bool = has_alternate and int(sentence_turn.get(id,0))%2==1
	sentence_turn[id] = int(sentence_turn.get(id,0))+1
	var item: Dictionary = (alternate if use_alternate else example).duplicate(true)
	item["contextId"] = ("transfer:" if use_alternate else "example:")+id
	return item

func _choices(word: Dictionary, item: Dictionary, kind: String) -> Array:
	var blank: Dictionary = item if item.has("cloze") else Cloze.build(item if kind=="sentence" else word.get("example",word),word)
	if not bool(blank.get("valid",false)): return []
	var choices: Array = [Cloze.option(word,blank.cloze,true)]
	var chosen_words: Array = [word]
	var labels: Dictionary = {str(choices[0].item.jp):true}
	var others: Array = words.duplicate()
	_shuffle(others)
	var limit: int = 3 if str(lesson.get("id","")).begins_with("basic-") else 4
	for candidate in others:
		if str(candidate.id)==str(word.id): continue
		var equivalent: bool = false
		for previous in chosen_words:
			if Cloze.same_answer(previous,candidate): equivalent = true;break
		if equivalent: continue
		var choice: Dictionary = Cloze.option(candidate,blank.cloze)
		var label: String = str(choice.item.jp)
		if label.is_empty() or labels.has(label): continue
		labels[label] = true
		chosen_words.append(candidate)
		choices.append(choice)
		if choices.size()==limit: break
	_shuffle(choices)
	return choices

func _shuffle(values: Array) -> void:
	for index in range(values.size()-1,0,-1):
		var other: int = rng.randi_range(0,index)
		var value = values[index]
		values[index] = values[other]
		values[other] = value

func _mission_task(mission: Dictionary, wave: int) -> Dictionary:
	var choices: Array = []
	var choice_items: Dictionary = {}
	var answer_word: Dictionary = {}
	for target in mission.get("targets",[]):
		var label: Dictionary = target.get("label",{})
		choices.append({"id":str(target.id),"label":str(label.get("jp",""))+" · "+str(label.get("ko",target.id)),"item":label.duplicate(true)})
		choice_items[str(target.id)] = label.duplicate(true)
		if str(target.id)==str(mission.get("answerId","")):
			answer_word = label.duplicate(true)
			for id in mission.get("itemIds",[]):
				if word_index.has(str(id)) and Cloze.same_answer(word_index[str(id)],label): answer_word["id"] = str(id);break
	var answer: String = str(mission.get("answerId",""))
	var valid: bool = false
	for choice in choices:
		if choice.id==answer: valid = true
	if not valid or choices.size()<2 or not mission.get("report") is Dictionary: return {}
	var blank: Dictionary = Cloze.build(mission.report,answer_word)
	if not bool(blank.valid): return {}
	var related_ids: Array = []
	for id in mission.get("itemIds",[]):
		if word_index.has(str(id)) and int(word_index[str(id)].lessonNumber)<=maximum_reached: related_ids.append(str(id))
	var representative: String = _choose_word(related_ids,false) if not related_ids.is_empty() else ""
	var presentation: Dictionary = mission.duplicate(true)
	presentation["questionItem"] = blank.questionItem
	presentation["revealItem"] = blank.revealItem
	presentation["cloze"] = blank.cloze
	presentation["choiceItems"] = choice_items
	return {"id":_attempt_id(wave,str(mission.id)),"kind":"context","item":mission.report.duplicate(true),"itemId":str(mission.id),"skill":"context","contextId":"mission:"+str(mission.id),"choices":choices,"answerId":answer,"mission":presentation,"representativeItemId":representative,"questionItem":blank.questionItem,"revealItem":blank.revealItem,"cloze":blank.cloze,"promptKo":"빈칸에 들어갈 일본어를 골라 원군을 보내십시오.","cueKo":str(blank.questionItem.get("ko","")),"showMeaning":true}

func _attempt_id(wave: int, item_id: String) -> String:
	task_counter += 1
	return "%s:%s:w%d:%s:%d" % [session_id,str(stage.get("id","lesson")),wave,item_id,task_counter]

func set_hinted(task_id: String) -> void:
	if not pending.is_empty() and str(pending.id)==task_id:
		hinted_tasks[task_id] = true

func skip_task(task: Dictionary) -> void:
	if pending.is_empty() or str(task.get("id",""))!=str(pending.id): return
	store.mark_exposure(str(pending.itemId),str(pending.skill),str(pending.contextId))
	var representative: String = str(pending.get("representativeItemId",""))
	if not representative.is_empty():
		store.mark_exposure(representative,"context",str(pending.contextId))
	last_item_id = representative if not representative.is_empty() else str(pending.itemId)
	pending = {}

func record(task: Dictionary, answer_id: String, hinted: bool) -> Dictionary:
	if pending.is_empty() or str(task.get("id",""))!=str(pending.id): return {"accepted":false,"duplicate":true,"correct":false}
	var valid_choice: bool = false
	for choice in pending.choices:
		if str(choice.id)==answer_id: valid_choice = true
	if not valid_choice: return {"accepted":false,"correct":false,"error":"선택지에 없는 답안입니다."}
	if hinted: set_hinted(str(pending.id))
	var used_hint: bool = hinted_tasks.has(str(pending.id))
	# Use the internally issued task, not an altered caller answer key.
	var correct: bool = answer_id==str(pending.answerId)
	var records: Array = [{"itemId":str(pending.itemId),"skill":str(pending.skill),"correct":correct,"hinted":used_hint,"contextId":str(pending.contextId),"attemptId":str(pending.id)+":item:"+str(pending.itemId)}]
	var representative: String = str(pending.get("representativeItemId",""))
	if not representative.is_empty():
		records.append({"itemId":representative,"skill":"context","correct":correct,"hinted":used_hint,"contextId":str(pending.contextId),"attemptId":str(pending.id)+":word:"+representative})
	var result: Dictionary = store.record_learning_batch(records)
	result["correct"] = correct
	result["hinted"] = used_hint
	result["kind"] = str(pending.kind)
	result["skill"] = str(pending.skill)
	result["itemId"] = str(pending.itemId)
	var status: Dictionary = store.learning_status(str(pending.itemId),str(pending.skill))
	result["mastered"] = status.mastered
	result["nextReviewAt"] = status.nextReviewAt
	if bool(result.accepted):
		last_item_id = representative if not representative.is_empty() else str(pending.itemId)
		pending = {}
	return result
