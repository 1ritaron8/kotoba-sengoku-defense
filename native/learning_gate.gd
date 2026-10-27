extends RefCounted
## A private all-correct assessment. Retry restores verified answers from the scoped progress checkpoint.
## It never records SRS or rewards; saved unlocks still require the complete scope.
const Cloze = preload("res://native/learning_cloze.gd")
var _lesson: Dictionary = {}
var _map_id: String = ""
var _scope_hash: String = ""
var _attempt_id: String = ""
var _questions: Array = []
var _index: int = 0
var _correct_count: int = 0
var _required_count: int = 0
var _complete: bool = false
var _failure: String = ""
var _ready: bool = false
var _rng := RandomNumberGenerator.new()
var _store: RefCounted
var _verified: Array = []

static func scope_hash(lesson: Dictionary) -> String:
	var scope: Dictionary = {"lessonId":str(lesson.get("id","")),"words":[],"grammar":lesson.get("grammarSteps",[]).duplicate(true)}
	for word in lesson.get("newWords",[]):
		scope.words.append({"id":str(word.get("id","")),"jp":str(word.get("jp","")),"reading":str(word.get("reading","")),"ko":str(word.get("ko","")),"parts":word.get("parts",[]),"example":word.get("example",{}),"transferExample":word.get("transferExample",{})})
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(scope,"",true).to_utf8_buffer())
	return hash.finish().hex_encode()

static func clean_checkpoint(lesson: Dictionary, map_id: String, value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("format")!=1 or value.get("mapId")!=map_id or value.get("lessonId")!=str(lesson.get("id","")) or value.get("scopeHash")!=scope_hash(lesson): return {}
	if not value.get("answers") is Array: return {}
	var expected: Array=[]
	var item_ids: Dictionary={}
	for word in lesson.get("newWords",[]):
		expected.append({"itemId":str(word.get("id","")),"answerId":str(word.get("id",""))})
	for step in lesson.get("grammarSteps",[]):
		expected.append({"itemId":str(step.get("id","")),"answerId":str(step.get("assessment",{}).get("answerId",""))})
	# A partial checkpoint can never claim completion. Only the final live
	# answer transaction writes a completed assessment and removes this state.
	if expected.is_empty() or value.answers.size()>=expected.size(): return {}
	for entry in expected:
		if str(entry.itemId).is_empty() or str(entry.answerId).is_empty() or item_ids.has(str(entry.itemId)): return {}
		item_ids[str(entry.itemId)]=true
	var tokens: Dictionary={}
	for index in range(value.answers.size()):
		var answer: Variant=value.answers[index]
		if not answer is Dictionary or answer.get("itemId")!=expected[index].itemId or answer.get("answerId")!=expected[index].answerId or not answer.get("questionId") is String: return {}
		var token: String=str(answer.questionId)
		if not token.ends_with(":"+str(index)+":"+str(expected[index].itemId)) or token.get_slice(":",0).length()!=32 or tokens.has(token): return {}
		tokens[token]=true
	return {"format":1,"mapId":map_id,"lessonId":str(lesson.get("id","")),"scopeHash":scope_hash(lesson),"answers":value.answers.duplicate(true)}

func bind_store(progress_store: RefCounted) -> void:
	_store=progress_store

func checkpoint() -> Dictionary:
	return {"format":1,"mapId":_map_id,"lessonId":str(_lesson.get("id","")),"scopeHash":_scope_hash,"answers":_verified.duplicate(true)}

func start(lesson: Dictionary, map_id: String, saved: Dictionary = {}) -> Dictionary:
	_lesson = lesson.duplicate(true)
	_map_id = map_id
	_scope_hash = scope_hash(_lesson)
	_attempt_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_questions = []
	_index = 0
	_correct_count = 0
	_verified=[]
	_complete = false
	_failure = ""
	_ready = false
	_rng.randomize()
	_required_count = _lesson.get("newWords",[]).size()+_lesson.get("grammarSteps",[]).size()
	if map_id.is_empty() or _lesson.get("newWords",[]).is_empty(): return _invalid("시험할 전장과 단어를 확인하지 못했습니다.")
	var stable_ids: Dictionary = {}
	for word in _lesson.get("newWords",[]):
		var id: String = str(word.get("id",""))
		if id.is_empty() or stable_ids.has(id): return _invalid("시험 단어의 식별자가 중복되었습니다.")
		stable_ids[id] = true
		var question: Dictionary = _word_question(word)
		if question.is_empty(): return _invalid("‘%s’의 빈칸 원문과 선택지를 확인하지 못했습니다." % str(word.get("jp","")))
		_questions.append(question)
	for step in _lesson.get("grammarSteps",[]):
		var id: String = str(step.get("id",""))
		if id.is_empty() or stable_ids.has(id): return _invalid("시험 문법의 식별자가 중복되었습니다.")
		stable_ids[id] = true
		var question: Dictionary = _grammar_question(step)
		if question.is_empty(): return _invalid("‘%s’의 문법 빈칸 원문과 뜻 단서를 확인하지 못했습니다." % str(step.get("titleKo",id)))
		_questions.append(question)
	if _questions.size()!=_required_count or _required_count<1: return _invalid("시험 범위를 모두 확인하지 못했습니다.")
	for index in range(_questions.size()):
		var question: Dictionary = _questions[index]
		question["id"] = _attempt_id+":"+str(index)+":"+str(question.itemId)
		var answer: String = str(question.answerId)
		for option in question.choices:
			var stable: String = str(option.id)
			option["itemId"] = stable
			option.id = question.id+":option:"+stable
			if stable==answer: question.answerId = option.id
		_shuffle(question.choices)
	_ready = true
	var restored: Dictionary=clean_checkpoint(_lesson,_map_id,saved)
	if not restored.is_empty():
		_verified=restored.answers.duplicate(true)
		_index=_verified.size()
		_correct_count=_index
	if _store!=null and not _store.save_gate_checkpoint(self):
		return _invalid(str(_store.save_error))
	var status: Dictionary = snapshot()
	status["ok"] = true
	return status

func matches_scope(lesson: Dictionary, map_id: String) -> bool:
	return _ready and _map_id==map_id and _scope_hash==scope_hash(lesson)

func retry() -> Dictionary:
	# Correct answers form a private prefix: a wrong answer, hint or skip ends
	# the round without advancing this index. Never rebuild/reset that prefix.
	if not _ready or _index>=_questions.size():
		var rejected: Dictionary=snapshot()
		rejected["ok"]=false
		rejected["errorKo"]="다시 풀 문제가 없거나 시험 범위를 확인하지 못했습니다."
		return rejected
	_attempt_id=Crypto.new().generate_random_bytes(16).hex_encode()
	for index in range(_index,_questions.size()):
		var question: Dictionary=_questions[index]
		var answer: String=""
		for option in question.choices:
			if str(option.id)==str(question.answerId): answer=str(option.itemId)
		question.id=_attempt_id+":"+str(index)+":"+str(question.itemId)
		for option in question.choices:
			option.id=question.id+":option:"+str(option.itemId)
			if str(option.itemId)==answer: question.answerId=option.id
		_shuffle(question.choices)
	_complete=false
	_failure=""
	var status: Dictionary=snapshot()
	status["ok"]=true
	return status

func current_task() -> Dictionary:
	if not _ready or _complete or _index>=_questions.size(): return {}
	var result: Dictionary = _questions[_index].duplicate(true)
	result.erase("answerId")
	result.erase("cloze")
	return result

func answer(choice_id: String) -> Dictionary:
	if not _ready or _complete or _index>=_questions.size(): return _rejected("이미 끝난 시험입니다.")
	var question: Dictionary = _questions[_index]
	var valid: bool = false
	for choice in question.choices:
		if str(choice.id)==choice_id: valid = true;break
	if not valid: return _rejected("현재 문제의 선택지가 아닙니다.")
	var correct: bool = choice_id==str(question.answerId)
	if correct:
		var stable_answer: String=""
		for option in question.choices:
			if str(option.id)==choice_id: stable_answer=str(option.itemId)
		_verified.append({"itemId":str(question.itemId),"answerId":stable_answer,"questionId":str(question.id)})
		_correct_count += 1
		_index += 1
		_complete = _index>=_questions.size()
		if _store!=null and not _store.save_gate_checkpoint(self):
			_verified.pop_back()
			_correct_count-=1
			_index-=1
			_complete=false
			return _rejected("정답 기록을 저장하지 못했습니다. 다시 선택해 주십시오. "+str(_store.save_error))
	else:
		_complete = true
		_failure = "incorrect"
	return _verdict(question,correct)

func hint() -> Dictionary:
	return _end_with_help("hinted")

func skip() -> Dictionary:
	return _end_with_help("skipped")

func snapshot() -> Dictionary:
	var passed: bool = _ready and _complete and _failure.is_empty() and _required_count>0 and _correct_count==_required_count and _questions.size()==_required_count
	return {"ready":_ready,"mapId":_map_id,"lessonId":str(_lesson.get("id","")),"scopeHash":_scope_hash,"attemptId":_attempt_id,"index":_index,"count":_questions.size(),"requiredCount":_required_count,"correctCount":_correct_count,"complete":_complete,"passed":passed,"failure":_failure}

func _invalid(message: String) -> Dictionary:
	_ready = false
	_complete = true
	_failure = "invalid"
	var result: Dictionary = snapshot()
	result["ok"] = false
	result["errorKo"] = message
	return result

func _rejected(message: String) -> Dictionary:
	var result: Dictionary = snapshot()
	result.merge({"accepted":false,"correct":false,"errorKo":message},true)
	return result

func _end_with_help(reason: String) -> Dictionary:
	if not _ready or _complete or _index>=_questions.size(): return _rejected("이미 끝난 시험입니다.")
	_complete = true
	_failure = reason
	return _verdict(_questions[_index],false)

func _verdict(question: Dictionary, correct: bool) -> Dictionary:
	var result: Dictionary = snapshot()
	result.merge({"accepted":true,"correct":correct,"correctChoiceId":str(question.answerId),"answerText":str(question.cloze.answerText),"cueKo":str(question.get("cueKo","")),"revealItem":question.revealItem.duplicate(true),"explanationKo":str(question.get("explanationKo",""))},true)
	return result

func _word_question(word: Dictionary) -> Dictionary:
	var blank: Dictionary = Cloze.build(word.get("example",{}),word)
	if not bool(blank.get("valid",false)) or str(blank.questionItem.get("ko","")).is_empty(): return {}
	var options: Array = [_test_option(Cloze.option(word,blank.cloze,true))]
	var used: Array = [word]
	var jp_seen: Dictionary = {str(options[0].item.jp):true}
	var others: Array = _lesson.get("newWords",[]).duplicate()
	_shuffle(others)
	var limit: int = 3 if str(_lesson.get("id","")).begins_with("basic-") else 4
	for candidate in others:
		var equivalent: bool = false
		for previous in used:
			if Cloze.same_answer(previous,candidate): equivalent = true;break
		if equivalent: continue
		var option: Dictionary = _test_option(Cloze.option(candidate,blank.cloze))
		if str(option.item.jp).is_empty() or jp_seen.has(str(option.item.jp)): continue
		jp_seen[str(option.item.jp)] = true
		options.append(option)
		used.append(candidate)
		if options.size()==limit: break
	if options.size()<2: return {}
	return {"kind":"gate_word","itemId":str(word.id),"wordId":str(word.id),"item":blank.revealItem,"questionItem":blank.questionItem,"revealItem":blank.revealItem,"cloze":blank.cloze,"choices":options,"answerId":str(word.id),"showMeaning":true,"cueKo":str(blank.questionItem.ko),"promptKo":"한국어 뜻에 맞는 일본어를 빈칸에 넣으십시오.","explanationKo":"‘%s’는 ‘%s’입니다." % [str(word.jp),str(word.ko)]}

func _grammar_question(step: Dictionary) -> Dictionary:
	var assessment: Variant = step.get("assessment")
	if not assessment is Dictionary or not assessment.get("item") is Dictionary or not assessment.get("targetSpan") is Dictionary: return {}
	var source: Dictionary = assessment.item.duplicate(true)
	source["targetSpan"] = assessment.targetSpan.duplicate(true)
	var word: Dictionary = {"id":str(step.id),"jp":str(source.targetSpan.get("text","")),"reading":str(source.targetSpan.get("reading","")),"ko":str(assessment.get("cueKo",source.get("ko","")))}
	var blank: Dictionary = Cloze.build(source,word)
	if not bool(blank.get("valid",false)) or str(blank.questionItem.get("ko","")).is_empty(): return {}
	var options: Array = []
	var ids: Dictionary = {}
	var labels: Dictionary = {}
	var answer_id: String = str(assessment.get("answerId",""))
	var answer_count: int = 0
	for candidate in assessment.get("choices",[]):
		var id: String = str(candidate.get("id",""))
		var jp: String = str(candidate.get("jp",""))
		if id.is_empty() or jp.is_empty() or ids.has(id) or labels.has(jp): return {}
		ids[id] = true
		labels[jp] = true
		var item: Dictionary = candidate.duplicate(true)
		if not item.has("parts"): item["parts"] = [{"text":jp,"reading":str(item.get("reading",""))}]
		options.append(_test_option({"id":id,"label":jp,"item":item}))
		if id==answer_id:
			if jp!=str(blank.cloze.answerText): return {}
			answer_count += 1
	if options.size()<2 or options.size()>4 or answer_count!=1: return {}
	return {"kind":"gate_grammar","itemId":str(step.id),"grammarId":str(step.id),"item":blank.revealItem,"questionItem":blank.questionItem,"revealItem":blank.revealItem,"cloze":blank.cloze,"choices":options,"answerId":answer_id,"showMeaning":true,"cueKo":str(assessment.get("cueKo",blank.questionItem.ko)),"promptKo":str(assessment.get("promptKo","한국어 문장 뜻에 맞는 문법 표현을 고르십시오.")),"explanationKo":str(assessment.get("explanationKo",step.get("explanationKo","")))}

func _test_option(option: Dictionary) -> Dictionary:
	var result: Dictionary = option.duplicate(true)
	result.item["ko"] = ""
	result.label = str(result.item.jp)
	return result

func _shuffle(values: Array) -> void:
	for index in range(values.size()-1,0,-1):
		var other: int = _rng.randi_range(0,index)
		var previous = values[index]
		values[index] = values[other]
		values[other] = previous
