extends RefCounted
const UnitGrowth = preload("res://native/unit_growth.gd")
const UnitSkills = preload("res://native/unit_skills.gd")

const SAVE_PATH = "user://progress.json"
const MAX_ARMY_LEVEL = 10
const SKILLS = ["meaning", "listening", "context"]
const DAY_SECONDS = 86400.0
const MIN_MASTER_SPAN = 72000.0
const AUDIO_DEFAULTS: Dictionary = {"masterVolume":1.0,"musicVolume":1.0,"effectsVolume":0.8,"voiceVolume":0.8}
var save_path: String = SAVE_PATH
var data: Dictionary = {"version": 3, "maps": {}, "words": {}, "settings": {"music": true, "voice": true, "effects":true,"masterVolume":1.0,"musicVolume":1.0,"effectsVolume":0.8,"voiceVolume":0.8,"battleMinutes":10}, "army":{"currency":180,"levels":{},"selected":"archer"}, "learning":{"items":{},"attempts":{},"lastClockAt":0.0}}
var save_error: String = ""
var read_error: String = ""
var _save_read_blocked: bool = false
var unit_catalog: Array = []
var hero_catalog: Array = []
var stage_numbers: Dictionary = {}
var stage_names: Dictionary = {}
var stage_previous: Dictionary = {}
var stage_lessons: Dictionary = {}
var vocabulary_ids: Dictionary = {}

func _init() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json"))
	if catalog is Dictionary:
		unit_catalog = catalog.get("units",[])
	var heroes = JSON.parse_string(FileAccess.get_file_as_string("res://native/hero_catalog.json"))
	if heroes is Dictionary:
		hero_catalog = heroes.get("heroes",[])
	var maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if maps is Array:
		var stages_by_number: Dictionary = {}
		for stage in maps:
			stage_numbers[str(stage.id)] = int(stage.stageNumber)
			stage_names[str(stage.id)] = str(stage.title)
			stages_by_number[int(stage.stageNumber)] = str(stage.id)
		for stage in maps:
			stage_previous[str(stage.id)] = str(stages_by_number.get(int(stage.stageNumber)-1,""))
	var curriculum = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	if curriculum is Dictionary:
		var lesson_number: int = 0
		for tier in ["basic","beginner","intermediate","advanced"]:
			for lesson in curriculum.get(tier,[]):
				lesson_number += 1
				for stage_id in stage_numbers:
					if int(stage_numbers[stage_id])==lesson_number: stage_lessons[stage_id] = lesson
				for word in lesson.get("newWords",[]):
					vocabulary_ids[str(word.id)] = true
	_sanitize_army()

func read_save() -> void:
	read_error = ""
	_save_read_blocked = false
	var primary = null
	var primary_parser: JSON = JSON.new()
	if FileAccess.file_exists(save_path) and primary_parser.parse(FileAccess.get_file_as_string(save_path))==OK:
		primary = primary_parser.data
	if primary is Dictionary and (primary.get("version") is int or primary.get("version") is float) and is_finite(float(primary.version)) and float(primary.version)>3:
		read_error = "더 새로운 버전의 저장 기록입니다. 기존 파일을 보존했습니다."
		_save_read_blocked = true
		return
	var loaded: Dictionary = _read_valid(save_path)
	if loaded.is_empty():
		loaded = _read_valid(save_path+".bak")
		if not loaded.is_empty():
			read_error = "손상된 저장 대신 이전 정상 기록을 복구했습니다."
		elif FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak"):
			read_error = "저장 기록을 읽을 수 없습니다. 기존 파일을 보존했습니다."
			_save_read_blocked = true
			return
		else:
			return
	for key in ["maps","words","settings"]:
		if loaded.get(key) is Dictionary:
			data[key] = loaded[key].duplicate(true)
	for id in data.words.keys():
		if not data.words[id] is Dictionary:
			data.words.erase(id)
			continue
		for counter in ["seen","correct","wrong","hinted","streak"]:
			data.words[id][counter] = _count(data.words[id].get(counter,0))
	for id in data.maps.keys():
		if not data.maps[id] is Dictionary or not stage_numbers.has(str(id)):
			data.maps.erase(id)
	for setting in ["music","voice","effects"]:
		if not data.settings.get(setting) is bool:
			data.settings[setting] = true
	for setting in AUDIO_DEFAULTS:
		data.settings[setting] = audio_volume(str(setting))
	var battle_minutes = data.settings.get("battleMinutes",10)
	if (battle_minutes is int or battle_minutes is float) and is_finite(float(battle_minutes)) and float(battle_minutes) in [10.0,20.0]:
		data.settings.battleMinutes = int(battle_minutes)
	else:
		data.settings.battleMinutes = 10
	if loaded.get("army") is Dictionary:
		data.army = loaded.army.duplicate(true)
	else:
		# The v1 migration preserves the existing first-clear funding contract.
		data.army = {"currency":180,"levels":{},"selected":"archer"}
		for id in data.maps:
			data.army.currency += 140+int(stage_numbers[id])*8
	data.learning = loaded.get("learning",{}).duplicate(true) if int(loaded.version)==3 and loaded.get("learning") is Dictionary else {}
	_sanitize_learning()
	_sanitize_army()
	data.version = 3
	# Old correctness/streak counters remain historical, never mastery evidence.

func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK: return {}
	var value = parser.data
	if not value is Dictionary: return {}
	var version = value.get("version",0)
	if not (version is int or version is float) or not is_finite(float(version)): return {}
	if float(version)!=floorf(float(version)) or int(version) not in [1,2,3]: return {}
	if not value.get("maps") is Dictionary or not value.get("words") is Dictionary: return {}
	return value

func _count(value: Variant) -> int:
	return clampi(int(value),0,100000000) if (value is int or value is float) and is_finite(float(value)) else 0

func audio_volume(key: String) -> float:
	var fallback: float = float(AUDIO_DEFAULTS.get(key,1.0))
	var value: Variant = data.settings.get(key,fallback)
	return clampf(float(value),0.0,1.0) if (value is int or value is float) and is_finite(float(value)) else fallback

func set_audio_volume(key: String, value: float) -> bool:
	if not AUDIO_DEFAULTS.has(key) or not is_finite(value):
		return false
	data.settings[key] = clampf(value,0.0,1.0)
	return true

func _timestamp(value: Variant) -> float:
	return clampf(float(value),0.0,253402300799.0) if (value is int or value is float) and is_finite(float(value)) else 0.0

func _new_skill() -> Dictionary:
	return {"exposures":0,"correct":0,"wrong":0,"hinted":0,"unhintedCorrect":0,"cleanSuccesses":0,"cleanStreak":0,"successfulDates":{},"successfulContexts":{},"firstCleanAt":0.0,"lastCleanAt":0.0,"lastExposureAt":0.0,"lastAttemptAt":0.0,"nextReviewAt":0.0,"lastOutcome":""}

func _sanitize_learning() -> void:
	var source: Dictionary = data.learning if data.get("learning") is Dictionary else {}
	var clean: Dictionary = {"items":{},"attempts":{},"assessments":{},"lastClockAt":0.0}
	var system_now: float = Time.get_unix_time_from_system()
	clean.lastClockAt = minf(_timestamp(source.get("lastClockAt",0)),system_now+300.0)
	if source.get("items") is Dictionary:
		for id in source.items:
			if not source.items[id] is Dictionary or str(id).is_empty(): continue
			var entry: Dictionary = {}
			for skill in SKILLS:
				if not source.items[id].get(skill) is Dictionary: continue
				var old: Dictionary = source.items[id][skill]
				var state: Dictionary = _new_skill()
				for key in ["exposures","correct","wrong","hinted","unhintedCorrect","cleanSuccesses","cleanStreak"]:
					state[key] = _count(old.get(key,0))
				for key in ["firstCleanAt","lastCleanAt","lastExposureAt","lastAttemptAt","nextReviewAt"]:
					state[key] = _timestamp(old.get(key,0))
				# A damaged far-future timestamp must not lock offline review away.
				for key in ["firstCleanAt","lastCleanAt","lastExposureAt","lastAttemptAt"]:
					if float(state[key])>system_now+300: state[key] = 0.0
				if float(state.nextReviewAt)>system_now+DAY_SECONDS*61: state.nextReviewAt = system_now
				state.lastOutcome = str(old.get("lastOutcome","")) if str(old.get("lastOutcome","")) in ["","correct","wrong","hinted"] else ""
				if old.has("lastExposureContext"):
					state["lastExposureContext"] = str(old.lastExposureContext)
				if old.get("successfulDates") is Dictionary:
					for day in old.successfulDates:
						var stamp: float = _timestamp(old.successfulDates[day])
						if stamp<=system_now+300 and _day(stamp)==str(day): state.successfulDates[str(day)] = stamp
				if old.get("successfulContexts") is Dictionary:
					for context in old.successfulContexts:
						if not str(context).is_empty() and _count(old.successfulContexts[context])>0: state.successfulContexts[str(context)] = _count(old.successfulContexts[context])
				entry[skill] = state
			clean.items[str(id)] = entry
	if source.get("attempts") is Dictionary:
		for id in source.attempts:
			var receipt = source.attempts[id]
			if receipt is Dictionary and not str(id).is_empty() and str(receipt.get("skill","")) in SKILLS:
				clean.attempts[str(id)] = receipt.duplicate(true)
	if source.get("assessments") is Dictionary:
		for id in source.assessments:
			var receipt = source.assessments[id]
			if not stage_numbers.has(str(id)) or not receipt is Dictionary: continue
			if receipt.get("passed")!=true or _count(receipt.get("correctCount",0))!=_count(receipt.get("count",0)) or _count(receipt.get("count",0))==0: continue
			if not receipt.get("scopeHash") is String or str(receipt.scopeHash).length()!=64: continue
			clean.assessments[str(id)] = {"passed":true,"correctCount":_count(receipt.correctCount),"count":_count(receipt.count),"scopeHash":str(receipt.scopeHash),"attemptId":str(receipt.get("attemptId","")),"passedAt":_timestamp(receipt.get("passedAt",0))}
	data.learning = clean

func _day(now: float) -> String:
	return Time.get_date_string_from_unix_time(int(now))

func _time(now: float = -1) -> float:
	var requested: float = Time.get_unix_time_from_system() if now<0 or not is_finite(now) else _timestamp(now)
	return maxf(requested,_timestamp(data.learning.get("lastClockAt",0)))

func _state(item_id: String, skill: String, create: bool = false) -> Dictionary:
	if not data.learning.items.has(item_id):
		if not create: return _new_skill()
		data.learning.items[item_id] = {}
	if not data.learning.items[item_id].has(skill):
		if not create: return _new_skill()
		data.learning.items[item_id][skill] = _new_skill()
	return data.learning.items[item_id][skill]

func _mastered(state: Dictionary, skill: String = "context") -> bool:
	var required_contexts: int = 2 if skill=="context" else 1
	return int(state.cleanSuccesses)>=3 and int(state.cleanStreak)>=3 and state.successfulDates.size()>=2 and state.successfulContexts.size()>=required_contexts and float(state.lastCleanAt)-float(state.firstCleanAt)>=MIN_MASTER_SPAN

func learning_status(item_id: String, skill: String = "meaning", now: float = -1) -> Dictionary:
	var state: Dictionary = _state(item_id,skill) if skill in SKILLS else _new_skill()
	var mastered: bool = _mastered(state,skill)
	var status: String = "mastered" if mastered else "developing"
	if state.lastOutcome in ["wrong","hinted"]: status = state.lastOutcome
	elif int(state.correct)==0 and int(state.wrong)==0: status = "exposed" if int(state.exposures)>0 else "new"
	var evidence_needed: Array = []
	if int(state.cleanSuccesses)<3: evidence_needed.append("무힌트 정답 3회")
	if state.successfulDates.size()<2 or float(state.lastCleanAt)-float(state.firstCleanAt)<MIN_MASTER_SPAN: evidence_needed.append("서로 다른 날짜에 재확인")
	if state.successfulContexts.size()<(2 if skill=="context" else 1): evidence_needed.append("다른 문장 확인" if skill=="context" else "출제 문맥 확인")
	var status_ko: String = "숙련" if mastered else "무힌트 확인 필요"
	if not mastered:
		if state.lastOutcome=="wrong": status_ko = "오답 우선 복습"
		elif state.lastOutcome=="hinted": status_ko = "힌트 없이 재확인"
		elif skill=="context" and state.successfulContexts.size()<2: status_ko = "다른 문장 확인 필요"
		elif int(state.cleanSuccesses)>=3: status_ko = "시간 두고 복습"
	return {"itemId":item_id,"skill":skill,"status":status,"statusKo":status_ko,"mastered":mastered,"nextReviewAt":float(state.nextReviewAt),"due":float(state.nextReviewAt)<=_time(now),"exposures":int(state.exposures),"correct":int(state.correct),"unhintedCorrect":int(state.unhintedCorrect),"wrong":int(state.wrong),"hinted":int(state.hinted),"cleanSuccesses":int(state.cleanSuccesses),"successfulDays":state.successfulDates.size(),"successfulContexts":state.successfulContexts.size(),"lastAttemptAt":float(state.lastAttemptAt),"needsContext":state.successfulContexts.size()<(2 if skill=="context" else 1),"evidenceNeeded":evidence_needed}

func mark_exposure(item_id: String, skill: String = "meaning", context_id: String = "", now: float = -1) -> void:
	if item_id.is_empty() or skill not in SKILLS or not is_finite(now): return
	var before: Dictionary = data.duplicate(true)
	var timestamp: float = _time(now)
	var state: Dictionary = _state(item_id,skill,true)
	state.exposures = int(state.exposures)+1
	state.lastExposureAt = timestamp
	state["lastExposureContext"] = context_id
	var legacy: Dictionary = data.words.get(item_id,{"seen":0,"correct":0,"wrong":0,"hinted":0,"streak":0})
	legacy.seen = _count(legacy.get("seen",0))+1
	legacy.last_seen = timestamp
	data.words[item_id] = legacy
	data.learning.lastClockAt = timestamp
	if not write_save(): data = before

func record_learning(item_id: String, skill: String, correct: bool, hinted: bool, context_id: String, attempt_id: String, now: float = -1) -> Dictionary:
	var result: Dictionary = record_learning_batch([{ "itemId":item_id,"skill":skill,"correct":correct,"hinted":hinted,"contextId":context_id,"attemptId":attempt_id}],now)
	var status: Dictionary = learning_status(item_id,skill,now)
	result["mastered"] = status.mastered
	result["nextReviewAt"] = status.nextReviewAt
	return result

func record_learning_batch(records: Array, now: float = -1) -> Dictionary:
	if not is_finite(now) or now>253402300799.0: return {"accepted":false,"error":"잘못된 학습 시각입니다."}
	if records.is_empty(): return {"accepted":false,"error":"학습 답안이 비어 있습니다."}
	var ids: Dictionary = {}
	for record in records:
		if not record is Dictionary: return {"accepted":false,"error":"잘못된 학습 답안입니다."}
		var attempt: String = str(record.get("attemptId",""))
		if str(record.get("itemId","")).is_empty() or str(record.get("skill","")) not in SKILLS or attempt.is_empty():
			return {"accepted":false,"error":"학습 항목과 답안 식별자가 필요합니다."}
		if ids.has(attempt) or data.learning.attempts.has(attempt): return {"accepted":false,"duplicate":true}
		ids[attempt] = true
	var before: Dictionary = data.duplicate(true)
	var timestamp: float = _time(now)
	var outcomes: Array = []
	for record in records:
		outcomes.append(_apply_learning(record,timestamp))
	data.learning.lastClockAt = timestamp
	if not write_save():
		data = before
		return {"accepted":false,"error":save_error,"outcomes":[]}
	return {"accepted":true,"outcomes":outcomes,"clockAdjusted":now>=0 and is_finite(now) and now<timestamp}

func _apply_learning(record: Dictionary, timestamp: float) -> Dictionary:
	var item_id: String = str(record.itemId)
	var skill: String = str(record.skill)
	var correct: bool = bool(record.get("correct",false))
	var hinted: bool = bool(record.get("hinted",false))
	var context: String = str(record.get("contextId",""))
	var state: Dictionary = _state(item_id,skill,true)
	state.lastAttemptAt = timestamp
	if correct: state.correct = int(state.correct)+1
	else: state.wrong = int(state.wrong)+1
	if hinted: state.hinted = int(state.hinted)+1
	if correct and not hinted:
		state.unhintedCorrect = int(state.unhintedCorrect)+1
		state.cleanSuccesses = int(state.cleanSuccesses)+1
		state.cleanStreak = int(state.cleanStreak)+1
		if int(state.cleanSuccesses)==1: state.firstCleanAt = timestamp
		state.lastCleanAt = timestamp
		state.successfulDates[_day(timestamp)] = timestamp
		if not context.is_empty() and context!="legacy": state.successfulContexts[context] = int(state.successfulContexts.get(context,0))+1
		state.lastOutcome = "correct"
		var days: int = 7 if _mastered(state,skill) else 1
		if _mastered(state,skill) and int(state.cleanSuccesses)>=6: days = 14
		if _mastered(state,skill) and int(state.cleanSuccesses)>=10: days = 30
		state.nextReviewAt = timestamp+DAY_SECONDS*days
	else:
		state.cleanSuccesses = 0
		state.cleanStreak = 0
		state.successfulDates = {}
		state.successfulContexts = {}
		state.firstCleanAt = 0.0
		state.lastCleanAt = 0.0
		state.lastOutcome = "hinted" if hinted else "wrong"
		state.nextReviewAt = timestamp+(1800.0 if hinted else 300.0)
	var legacy: Dictionary = data.words.get(item_id,{"seen":0,"correct":0,"wrong":0,"hinted":0,"streak":0})
	legacy.seen = _count(legacy.get("seen",0))+1
	legacy["last_seen"] = timestamp
	legacy["correct" if correct else "wrong"] = _count(legacy.get("correct" if correct else "wrong",0))+1
	if hinted: legacy.hinted = _count(legacy.get("hinted",0))+1
	legacy.streak = _count(legacy.get("streak",0))+1 if correct and not hinted else 0
	data.words[item_id] = legacy
	data.learning.attempts[str(record.attemptId)] = {"itemId":item_id,"skill":skill,"correct":correct,"hinted":hinted,"contextId":context,"at":timestamp}
	return learning_status(item_id,skill,timestamp)

func review_ids(eligible_ids: Array, limit: int, now: float = -1) -> Array:
	if limit<=0: return []
	var seen: Dictionary = {}
	var scored: Array = []
	var timestamp: float = _time(now)
	for raw_id in eligible_ids:
		var id: String = str(raw_id)
		if id.is_empty() or seen.has(id): continue
		seen[id] = true
		var score: float = 0.0
		var oldest: float = timestamp
		for skill in SKILLS:
			var state: Dictionary = _state(id,skill)
			if state.lastOutcome=="wrong": score = maxf(score,100.0)
			elif state.lastOutcome=="hinted": score = maxf(score,90.0)
			elif int(state.correct)>0 and float(state.nextReviewAt)<=timestamp: score = maxf(score,60.0)
			elif int(state.exposures)>0 or int(state.correct)>0: score = maxf(score,30.0)
			if float(state.lastAttemptAt)>0: oldest = minf(oldest,float(state.lastAttemptAt))
		var age: float = clampf((timestamp-oldest)/DAY_SECONDS,0.0,30.0)*.01
		scored.append({"id":id,"score":score+age})
	scored.sort_custom(func(a,b): return float(a.score)>float(b.score) if a.score!=b.score else str(a.id)<str(b.id))
	var result: Array = []
	for index in range(mini(limit,scored.size())): result.append(scored[index].id)
	return result

func _sanitize_army() -> void:
	var army: Dictionary = data.get("army",{})
	var currency = army.get("currency",180)
	army.currency = clampi(int(currency),0,100000000) if (currency is int or currency is float) and is_finite(float(currency)) else 180
	if not army.get("levels") is Dictionary:
		army.levels = {}
	var clean_levels: Dictionary = {}
	for definition in unit_catalog:
		var level = army.levels.get(str(definition.id),1)
		clean_levels[str(definition.id)] = clampi(int(level),1,MAX_ARMY_LEVEL) if (level is int or level is float) and is_finite(float(level)) else 1
	army.levels = clean_levels
	var clean_training: Dictionary = {}
	if army.get("training") is Dictionary:
		for definition in unit_catalog:
			var id: String = str(definition.id)
			if army.training.get(id) is bool and bool(army.training.get(id,false)) and data.maps.size()>=int(definition.get("unlockClears",0)):
				clean_training[id] = true
	army.training = clean_training
	data.army = army
	var selected: String = str(army.get("selected","archer"))
	data.army.selected = selected if selected in unlocked_units() else "archer"

func unlocked_units() -> Array:
	var result: Array = []
	for definition in unit_catalog:
		if data.maps.size() >= int(definition.get("unlockClears",0)):
			result.append(str(definition.id))
	return result

func unit_definition(id: String) -> Dictionary:
	for definition in unit_catalog:
		if str(definition.id)==id:
			return definition
	return {}

func is_unit_trained(id: String) -> bool:
	var training = data.army.get("training",{})
	return id in unlocked_units() and training is Dictionary and training.get(id) is bool and bool(training.get(id,false))

func record_unit_training(id: String) -> Dictionary:
	if not id in unlocked_units():
		return {"ok":false,"message":"아직 해금되지 않은 병종입니다."}
	if is_unit_trained(id): return {"ok":true,"recorded":false}
	var before: Dictionary = data.army.duplicate(true)
	if not data.army.get("training") is Dictionary: data.army.training = {}
	data.army.training[id] = true
	if not write_save():
		data.army = before
		return {"ok":false,"message":save_error}
	return {"ok":true,"recorded":true}

func army_level(id: String) -> int:
	return clampi(int(data.army.levels.get(id,1)),1,MAX_ARMY_LEVEL)

func army_recruit_cost(id: String) -> int:
	return UnitGrowth.recruit_cost(unit_definition(id),army_level(id))

func army_skills(id: String, level_override: int = -1) -> Array:
	var result: Array = []
	var level: int = army_level(id) if level_override<0 else clampi(level_override,1,MAX_ARMY_LEVEL)
	for entry in unit_definition(id).get("skillUnlocks",[]):
		var skill: Dictionary = entry.duplicate(true)
		skill["unlocked"] = level>=int(skill.level)
		result.append(skill)
	return result

func campaign_stage() -> int:
	var latest: int = 1
	for stage_id in stage_numbers:
		if map_cleared(str(stage_id)) or map_unlocked(str(stage_id)):
			latest = maxi(latest,int(stage_numbers[stage_id]))
	return latest

func army_commander(id: String, stage_override: int = -1) -> Dictionary:
	var stage: int = campaign_stage() if stage_override<0 else clampi(stage_override,1,40)
	var wanted: String = "hachisuka_iemasa" if id=="ninja" and stage>=35 else "hachisuka_masakatsu" if id=="ninja" else ""
	for entry in hero_catalog:
		if str(entry.unitId)!=id or (not wanted.is_empty() and str(entry.id)!=wanted):
			continue
		var hero: Dictionary = entry.duplicate(true)
		hero["joined"] = stage>=int(hero.joinStage)
		hero["displayRoleKo"] = "부대 지휘관" if hero.joined else "명장 모티브 · 합류 전"
		hero["adaptationKo"] = "병종과 능력은 게임 각색입니다. 전장 병사는 일반 병사입니다."
		return hero
	return {}

func army_upgrade_cost(id: String) -> int:
	var level: int = army_level(id)
	return 100 + level*40 + (level-1)*(level-1)*12

func army_evolution(id: String, level_override: int = -1) -> Dictionary:
	var definition: Dictionary = unit_definition(id)
	if definition.is_empty():
		return {}
	var level: int = army_level(id) if level_override<0 else clampi(level_override,1,MAX_ARMY_LEVEL)
	return UnitGrowth.evolution(definition,level)

func army_stats(id: String, level_override: int = -1) -> Dictionary:
	var definition: Dictionary = unit_definition(id)
	if definition.is_empty():
		return {}
	var level: int = army_level(id) if level_override < 0 else clampi(level_override,1,MAX_ARMY_LEVEL)
	var unit: Dictionary={"type":id,"campaignLevel":level,"elevation":0,"definition":definition}
	var growth: Dictionary=UnitGrowth.factors(unit,definition)
	var preview=UnitSkills.new()
	var modifiers: Dictionary=preview.stat_modifiers(unit)
	var support: Dictionary=preview.support_stats(unit)
	return {"damage":float(definition.damage)*float(growth.damage)*float(modifiers.damageFactor),"range":float(definition.range)*float(growth.range)*float(modifiers.rangeFactor),"interval":maxf(.25,float(definition.interval)*float(growth.interval)*float(modifiers.intervalFactor)),"level":level,"evolution":int(growth.evolutionStage),"health":UnitGrowth.max_health(unit,definition),"armor":UnitGrowth.armor(unit,preview.has_skill(unit,"samurai_armor")),"healAmount":float(support.healAmount) if id=="monk" else 0.0,"healInterval":float(support.healInterval),"supportStats":support}

func upgrade_army_unit(id: String) -> Dictionary:
	if not id in unlocked_units():
		return {"ok":false,"message":"아직 해금되지 않은 병력입니다."}
	var level: int = army_level(id)
	if level >= MAX_ARMY_LEVEL:
		return {"ok":false,"message":"최대 훈련 단계입니다."}
	var cost: int = army_upgrade_cost(id)
	if int(data.army.currency)<cost:
		return {"ok":false,"message":"영구 강화에 필요한 군자금이 부족합니다."}
	var before: Dictionary = data.army.duplicate(true)
	data.army.currency -= cost
	data.army.levels[id] = level+1
	if not write_save():
		data.army = before
		return {"ok":false,"message":save_error}
	var evolved: bool = int(army_evolution(id,level+1).stage)>int(army_evolution(id,level).stage)
	var newly_unlocked: Array = []
	for skill in army_skills(id):
		if int(skill.level)==level+1:
			newly_unlocked.append(skill)
	var message: String = "%s 진화!" % str(army_evolution(id).name) if evolved else "%s 훈련 Lv.%d 완료" % [str(unit_definition(id).name),level+1]
	if not newly_unlocked.is_empty():
		message += " · "+str(newly_unlocked[0].titleKo)+" 해금"
	return {"ok":true,"level":level+1,"cost":cost,"evolved":evolved,"skillsUnlocked":newly_unlocked,"message":message}

func select_army_unit(id: String) -> bool:
	if not id in unlocked_units():
		return false
	var before: String = str(data.army.selected)
	data.army.selected = id
	if not write_save():
		data.army.selected = before
		return false
	return true

func write_save() -> bool:
	if _save_read_blocked:
		save_error = "손상된 기존 저장을 보존하기 위해 새 기록 저장을 중단했습니다."
		return false
	data.version = 3
	var serialized: String = JSON.stringify(data)
	if not _write_complete(save_path+".tmp",serialized): return false
	var error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path))
	if error!=OK:
		save_error = "진행 상황 저장에 실패했습니다."
		return false
	# Primary rename is the transaction commit. Mirror that same committed
	# receipt set so corruption recovery also rejects the latest answer replay.
	# Backup failure cannot roll back an already committed primary transaction.
	if not _write_complete(save_path+".bak.tmp",serialized) or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".bak.tmp"),ProjectSettings.globalize_path(save_path+".bak"))!=OK:
		save_error = "진행 상황은 저장했지만 복구 사본을 갱신할 수 없습니다."
	else:
		save_error = ""
	return true

func _write_complete(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		save_error = "진행 상황을 저장할 수 없습니다."
		return false
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		save_error = "진행 상황을 저장할 공간이나 쓰기 권한이 부족합니다."
		return false
	if FileAccess.get_file_as_string(path)!=text:
		save_error = "저장한 진행 상황을 다시 확인할 수 없습니다."
		return false
	return true

func record_word(id: String, correct: bool, hinted: bool) -> void:
	var nonce: String = Crypto.new().generate_random_bytes(16).hex_encode()
	record_learning(id,"meaning",correct,hinted,"legacy","legacy:"+nonce)

func mark_seen(id: String) -> void:
	mark_exposure(id,"meaning","legacy")

func map_cleared(id: String) -> bool:
	var record = data.maps.get(id,{})
	return stage_numbers.has(id) and record is Dictionary and not record.is_empty() and int(record.get("wins",1))>0

func campaign_unified() -> bool:
	for id in stage_numbers:
		if int(stage_numbers[id])==40: return map_cleared(str(id)) and map_unlocked(str(id))
	return false

func map_unlocked(id: String) -> bool:
	if not stage_numbers.has(id): return false
	if int(stage_numbers[id])==1: return true
	var previous: String = previous_map(id)
	return not previous.is_empty() and map_cleared(previous) and map_assessed(previous)

func previous_map(id: String) -> String:
	return str(stage_previous.get(id,""))

func map_assessed(id: String) -> bool:
	var receipt = data.learning.get("assessments",{}).get(id,{})
	if not stage_lessons.has(id) or not receipt is Dictionary or receipt.get("passed")!=true: return false
	var lesson: Dictionary = stage_lessons[id]
	var required: int = lesson.get("newWords",[]).size()+lesson.get("grammarSteps",[]).size()
	if int(receipt.get("correctCount",0))!=required or int(receipt.get("count",0))!=required: return false
	var gate_script = load("res://native/learning_gate.gd")
	return gate_script!=null and str(receipt.get("scopeHash",""))==str(gate_script.scope_hash(lesson))

func record_assessment(gate: RefCounted) -> bool:
	var receipt: Dictionary = gate.snapshot()
	var id: String = str(receipt.get("mapId",""))
	if not map_cleared(id) or not map_unlocked(id) or receipt.get("passed")!=true or receipt.get("complete")!=true: return false
	var before: Dictionary = data.duplicate(true)
	if not data.learning.get("assessments") is Dictionary: data.learning["assessments"] = {}
	receipt["passedAt"] = Time.get_unix_time_from_system()
	data.learning.assessments[id] = receipt.duplicate(true)
	if not map_assessed(id) or not write_save():
		data = before
		return false
	return true

func map_lock_reason(id: String) -> String:
	if map_unlocked(id): return ""
	var previous: String = previous_map(id)
	if not previous.is_empty():
		var name_ko: String = "%02d단계 %s" % [int(stage_numbers[previous]),str(stage_names.get(previous,"이전 전장")).split(" · ")[0]]
		if not map_cleared(previous): return "잠김 · %s 클리어와 학습 시험 통과 필요" % name_ko
		if not map_assessed(previous): return "잠김 · %s 학습 시험 전 문항 정답 필요" % name_ko
	return "출진할 수 없는 전장입니다."

func complete_map(id: String, summary: Dictionary) -> Dictionary:
	if not stage_numbers.has(id):
		return {"currency":0,"unlocked":[],"firstClear":false}
	var before: Dictionary = data.duplicate(true)
	var unlocked_before: Array = unlocked_units()
	var previous: Dictionary = data.maps.get(id, {})
	var first_clear: bool = previous.is_empty()
	var reward: int = (140+int(stage_numbers[id])*8) if first_clear else (40+int(stage_numbers[id])*2)
	reward += clampi(int(summary.get("correct",0)),0,20)*5
	var record: Dictionary = summary.duplicate(true)
	record["wins"] = int(previous.get("wins", 0)) + 1
	record["finished_at"] = Time.get_unix_time_from_system()
	data.maps[id] = record
	data.army.currency = mini(100000000,int(data.army.currency)+reward)
	var new_unlocks: Array = []
	for unit_id in unlocked_units():
		if not unit_id in unlocked_before:
			new_unlocks.append(unit_id)
	if not write_save():
		data = before
		return {"currency":0,"unlocked":[],"firstClear":false,"saved":false,"error":save_error}
	return {"currency":reward,"unlocked":new_unlocks,"firstClear":first_clear}

func mastered_count() -> int:
	var count: int = 0
	for id in data.learning.items:
		if vocabulary_ids.has(str(id)) and _mastered(_state(str(id),"meaning"),"meaning") and _mastered(_state(str(id),"context"),"context"):
			count += 1
	return count
