extends SceneTree
const Gate = preload("res://native/learning_gate.gd")
const Cloze = preload("res://native/learning_cloze.gd")
var checks: int = 0
var failures: Array = []
var evidence: Dictionary = {"lessons":[],"words":0,"grammar":0,"edgeCases":[]}
var context: String = ""
var curriculum: Dictionary
var plans: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures.append(context+" · "+note)
		if failures.size()<=25: push_error("GATE "+context+" · "+note)

func option_id(task: Dictionary, stable_id: String) -> String:
	for option in task.get("choices",[]):
		if str(option.itemId)==stable_id: return str(option.id)
	return ""

func all_content() -> void:
	var lesson_maps: Dictionary = {}
	for id in plans.stages: lesson_maps[str(plans.stages[id].lessonId)] = str(id)
	for tier in ["basic","beginner","intermediate","advanced"]:
		for lesson in curriculum[tier]:
			context = str(lesson.id)
			var original: Dictionary = lesson.duplicate(true)
			var gate = Gate.new()
			var opened: Dictionary = gate.start(lesson,str(lesson_maps[str(lesson.id)]))
			var required: int = lesson.newWords.size()+lesson.get("grammarSteps",[]).size()
			check(bool(opened.get("ok",false)),"Actual lesson starts with every valid word and grammar question: "+str(opened.get("errorKo","")))
			if not bool(opened.get("ok",false)): continue
			check(opened.count==required and opened.requiredCount==required and opened.scopeHash==Gate.scope_hash(lesson) and opened.index==0 and not opened.passed,"Fresh attempt has exact scope/hash/count and no premature pass")
			var question_ids: Dictionary = {}
			var word_ids: Dictionary = {}
			var grammar_ids: Dictionary = {}
			for index in range(required):
				var task: Dictionary = gate.current_task()
				check(not task.is_empty() and not task.has("answerId") and not task.has("cloze"),"Current public question contains no answer key or private span descriptor")
				if task.is_empty(): continue
				var stable: String = str(task.wordId) if task.kind=="gate_word" else str(task.grammarId)
				var truth: String = stable
				var word: Dictionary = {}
				var source: Dictionary = {}
				if task.kind=="gate_word":
					word = lesson.newWords[index]
					source = word.example
					word_ids[stable] = true
					evidence.words += 1
				else:
					var step: Dictionary = lesson.grammarSteps[index-lesson.newWords.size()]
					truth = str(step.assessment.answerId)
					source = step.assessment.item.duplicate(true)
					source["targetSpan"] = step.assessment.targetSpan
					word = {"id":stable,"jp":step.assessment.targetSpan.text,"reading":step.assessment.targetSpan.reading,"ko":source.ko}
					grammar_ids[stable] = true
					evidence.grammar += 1
				var blank: Dictionary = Cloze.build(source,word)
				check(bool(blank.valid) and task.questionItem.jp==blank.questionItem.jp and task.revealItem.jp==source.jp,"Gate asks one real lexical/grammar source span and restores its original sentence")
				check(task.showMeaning and not str(task.cueKo).is_empty() and task.questionItem.ko==source.ko,"Korean sentence/meaning cue distinguishes otherwise plausible Japanese completions")
				var choices: Dictionary = {}
				for option in task.choices:
					choices[str(option.id)] = true
					check(str(option.label)==str(option.item.jp) and str(option.item.get("ko","")).is_empty(),"Assessment option exposes Japanese and furigana, without a matching Korean answer translation")
					check(str(option.id).begins_with(str(opened.attemptId)+":"+str(index)+":"),"Choice token is bound to the current attempt and question")
				check(choices.size()==task.choices.size() and not question_ids.has(str(task.id)),"Question and choice IDs are unique")
				question_ids[str(task.id)] = true
				var selected: String = option_id(task,truth)
				check(not selected.is_empty(),"Independent source answer is a visible option")
				var forged: Dictionary = task.duplicate(true)
				forged["answerId"] = "foreign"
				forged.questionItem.jp = "改ざん"
				forged.choices[0].id = "foreign"
				check(gate.current_task()==task,"Mutating a public task cannot alter the private question/answer")
				var before: Dictionary = gate.snapshot()
				var foreign: Dictionary = gate.answer("foreign")
				check(not foreign.accepted and gate.snapshot()==before,"Foreign choice ID cannot advance or finish the assessment")
				var result: Dictionary = gate.answer(selected)
				check(result.accepted and result.correct and result.correctChoiceId==selected and result.correctCount==index+1,"Exactly the independently correct source answer is accepted")
				check(result.revealItem.jp==source.jp and result.answerText==blank.cloze.answerText and not str(result.explanationKo).is_empty(),"Submitted answer returns original Japanese plus Korean explanation")
				check(result.passed==(index==required-1) and result.complete==(index==required-1),"Only the final all-correct answer can pass this fresh attempt")
				var after: Dictionary = gate.snapshot()
				check(not gate.answer(selected).accepted and gate.snapshot()==after,"Duplicate/previous-question callback cannot answer the next question or repeat completion")
			check(gate.current_task().is_empty() and gate.snapshot().passed and gate.snapshot().correctCount==required,"All required items are exhausted exactly once before pass")
			check(word_ids.size()==lesson.newWords.size() and grammar_ids.size()==lesson.get("grammarSteps",[]).size() and lesson==original,"Every new word and grammar step is tested without changing curriculum")
			evidence.lessons.append(gate.snapshot())
	check(evidence.lessons.size()==40 and evidence.words==900,"All40 maps and all900 new words receive their own assessment")

func failure_cases() -> void:
	context = "failure / hint / skip / retry / stale callback"
	var lesson: Dictionary = curriculum.basic[0]
	var gate = Gate.new()
	gate.start(lesson,"basic-forest")
	var task: Dictionary = gate.current_task()
	var expected: String = option_id(task,str(task.wordId))
	var wrong: String = ""
	for option in task.choices:
		if str(option.id)!=expected: wrong = str(option.id);break
	var result: Dictionary = gate.answer(wrong)
	check(result.accepted and not result.correct and result.complete and not result.passed and result.failure=="incorrect" and result.correctChoiceId==expected,"First incorrect answer ends the entire attempt without pass and reveals the source answer")
	check(gate.current_task().is_empty() and not gate.answer(expected).accepted and not gate.snapshot().passed,"A later correct callback cannot repair an already failed attempt")
	var old_attempt: String = str(gate.snapshot().attemptId)
	var retry: Dictionary = gate.retry()
	check(retry.ok and retry.index==0 and retry.correctCount==0 and retry.attemptId!=old_attempt and retry.scopeHash==Gate.scope_hash(lesson),"Retry starts a fresh nonce at the first word with the same content scope")
	var before: Dictionary = gate.snapshot()
	check(not gate.answer(expected).accepted and gate.snapshot()==before,"An earlier attempt's correct option cannot answer the retried first question")
	result = gate.hint()
	check(result.accepted and result.complete and not result.passed and result.failure=="hinted" and not str(result.revealItem.jp).is_empty(),"Hint restores the full source but makes this assessment unable to pass")
	check(not gate.hint().accepted and not gate.skip().accepted,"Repeated help callbacks cannot revive or alter the terminal attempt")
	gate.retry()
	result = gate.skip()
	check(result.accepted and result.complete and not result.passed and result.failure=="skipped","Leaving the assessment never grants unlock eligibility")
	gate.retry()
	for index in range(lesson.newWords.size()):
		task = gate.current_task()
		gate.answer(option_id(task,str(task.wordId)))
	check(not gate.snapshot().passed and not gate.snapshot().complete and gate.current_task().kind=="gate_grammar","Vocabulary-only completion cannot bypass required grammar")
	result = gate.skip()
	check(not result.passed and result.correctCount==lesson.newWords.size(),"Skipping the final grammar section still fails the complete assessment")
	evidence.edgeCases.append({"case":context,"state":gate.snapshot()})

func malformed_scope_cases() -> void:
	context = "scope hash / malformed metadata"
	var lesson: Dictionary = curriculum.basic[0].duplicate(true)
	var hash: String = Gate.scope_hash(lesson)
	var changed: Dictionary = lesson.duplicate(true)
	changed.newWords[0].ko = "다른 뜻"
	check(Gate.scope_hash(changed)!=hash,"Changing assessed word identity/meaning invalidates its scope hash")
	changed = lesson.duplicate(true)
	changed.grammarSteps[0].assessment.cueKo += " 새 지시"
	check(Gate.scope_hash(changed)!=hash,"Changing grammar assessment meaning/constraint invalidates its scope hash")
	var reversed: Dictionary = {}
	var keys: Array = lesson.keys()
	keys.reverse()
	for key in keys: reversed[key] = lesson[key]
	check(Gate.scope_hash(reversed)==hash,"Canonical hash is independent of dictionary insertion order")
	var gate = Gate.new()
	changed = lesson.duplicate(true)
	changed.newWords[0].example.targetSpan.start = 999
	var failed: Dictionary = gate.start(changed,"basic-forest")
	check(not failed.ok and not failed.passed and not str(failed.errorKo).is_empty() and gate.current_task().is_empty(),"Invalid word target offset cannot launch a reduced or falsely passing scope")
	changed = lesson.duplicate(true)
	changed.grammarSteps[0].assessment.answerId = str(changed.grammarSteps[0].assessment.choices[1].id)
	failed = gate.start(changed,"basic-forest")
	check(not failed.ok and not failed.passed,"A grammar answer key conflicting with the exact masked source is rejected")
	changed = lesson.duplicate(true)
	changed.grammarSteps[0].assessment.item.ko = ""
	failed = gate.start(changed,"basic-forest")
	check(not failed.ok and not failed.passed,"Missing Korean semantic cue cannot yield an ambiguous grammar question")
	changed = lesson.duplicate(true)
	changed.newWords.append(changed.newWords[0].duplicate(true))
	failed = gate.start(changed,"basic-forest")
	check(not failed.ok and not failed.passed,"Duplicate stable vocabulary IDs cannot manufacture an all-correct count")
	check(not gate.start(lesson,"").ok and not gate.start({"newWords":[],"grammarSteps":[]},"basic-forest").ok,"Empty map/word scope never passes")
	evidence.edgeCases.append({"case":context,"state":gate.snapshot()})

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/learning-gate/"): push_error("Gate QA refuses the player's profile");quit(2);return
	curriculum = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	plans = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	all_content()
	failure_cases()
	malformed_scope_cases()
	var report: Dictionary = {"checks":checks,"failures":failures,"evidence":evidence,"scope":"Independent source-answer ground truth for all40 actual map/lesson scopes, all900 vocabulary and every authored grammar assessment. Private answer IDs, real lexical/grammar source spans, meaning cues without Korean answer labels, unique attempt-bound options, full all-correct completion, hint/wrong/skip/duplicate/retry/stale protection, immutable caller copies and canonical scope hash invalidation. No SRS, rewards, campaign save or GPU."}
	var path: String = "user://qa_learning_gate_packed.json" if "--packed" in OS.get_cmdline_user_args() else "res://tests/qa_learning_gate_headless.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if output==null: quit(2);return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("LEARNING_GATE ",checks," checks / ",failures.size()," failures / ",evidence.words," words / ",evidence.grammar," grammar; report=",ProjectSettings.globalize_path(path))
	quit(0 if failures.is_empty() else 1)
