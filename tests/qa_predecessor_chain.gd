extends SceneTree
const Store = preload("res://native/progress.gd")
const Gate = preload("res://native/learning_gate.gd")
const Cloze = preload("res://native/learning_cloze.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(note)
		push_error("PREDECESSOR_CHAIN: "+note)

func certificate(lesson: Dictionary) -> Dictionary:
	var count: int = lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
	return {"passed":true,"count":count,"correctCount":count,"scopeHash":Gate.scope_hash(lesson)}

func correct_choice(task: Dictionary, lesson: Dictionary) -> String:
	var answer: String = ""
	if task.has("wordId"):
		for word in lesson.newWords:
			if str(word.id)==str(task.wordId): answer=str(Cloze.build(word.example,word).cloze.answerText)
	else:
		for step in lesson.get("grammarSteps",[]):
			if str(step.id)==str(task.get("grammarId","")):
				for choice in step.assessment.choices:
					if str(choice.id)==str(step.assessment.answerId): answer=str(choice.jp)
	for choice in task.get("choices",[]):
		if str(choice.get("item",{}).get("jp",""))==answer: return str(choice.id)
	return ""

func run() -> void:
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	var store: RefCounted = Store.new()
	store.save_path="user://predecessor-chain.json"
	check(store.map_unlocked(str(maps[0].id)),"Only stage one begins unlocked")
	check(not store.map_unlocked("unknown-stage"),"Unknown stages stay locked")
	for index in range(1,maps.size()):
		var current: String=str(maps[index].id)
		var previous: String=str(maps[index-1].id)
		store.data.maps={}
		store.data.learning["assessments"]={}
		check(store.previous_map(current)==previous,"Immediate predecessor: "+current)
		check(not store.map_unlocked(current),"No previous clear remains locked: "+current)
		check("%02d단계"%int(maps[index-1].stageNumber) in store.map_lock_reason(current),"Lock names the exact previous stage: "+current)
		store.data.maps[previous]={"wins":1}
		check(not store.map_unlocked(current),"A clear without learning certification remains locked: "+current)
		var receipt: Dictionary=certificate(store.stage_lessons[previous])
		store.data.learning.assessments[previous]=receipt
		check(store.map_unlocked(current),"Only the direct previous clear and certificate are required: "+current)
		if index<maps.size()-1:
			check(not store.map_unlocked(str(maps[index+1].id)),"The chain never skips the current stage: "+current)
		receipt.correctCount-=1
		check(not store.map_unlocked(current),"Incomplete answers cannot unlock: "+current)
		receipt.correctCount+=1
		receipt.scopeHash="outdated-curriculum"
		check(not store.map_unlocked(current),"An outdated learning scope cannot unlock: "+current)
	store.data.maps={str(maps[3].id):{"wins":1}}
	store.data.learning.assessments={str(maps[3].id):certificate(store.stage_lessons[str(maps[3].id)])}
	check(store.map_unlocked(str(maps[4].id)),"A recovered valid stage-four record unlocks stage five without checking one through three")
	check(store.write_save(),"The isolated valid chain record is saved")
	var reopened: RefCounted=Store.new()
	reopened.save_path=store.save_path
	reopened.read_save()
	check(reopened.map_unlocked(str(maps[4].id)),"The immediate predecessor rule survives save and reload")
	store.data.maps={str(maps[0].id):{"wins":1}}
	store.data.learning.assessments={}
	var gate: RefCounted=Gate.new()
	var lesson: Dictionary=store.stage_lessons[str(maps[0].id)]
	check(bool(gate.start(lesson,str(maps[0].id)).get("ok",false)),"The real first-stage assessment starts")
	for unused in range(lesson.newWords.size()+lesson.get("grammarSteps",[]).size()):
		var task: Dictionary=gate.current_task()
		var choice: String=correct_choice(task,lesson)
		check(not choice.is_empty(),"An independently read lesson answer is in the issued assessment")
		if choice.is_empty(): break
		check(bool(gate.answer(choice).get("correct",false)),"The real assessment accepts the correct choice")
	check(store.record_assessment(gate),"A real all-correct exam receipt is accepted")
	check(store.map_unlocked(str(maps[1].id)),"The real accepted receipt opens the next stage")
	check(not store.map_unlocked(str(maps[2].id)),"That receipt cannot open a later stage")
	print("PREDECESSOR_CHAIN checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
