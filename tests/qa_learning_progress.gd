extends SceneTree
## Real save, reload, corruption and task tests in workspace-isolated user data.
const Store = preload("res://native/progress.gd")
const Session = preload("res://native/learning_session.gd")
const T = 1704067200.0 # 2024-01-01 UTC; deterministic past dates survive reload.
var checks: int = 0
var failures: Array = []
var run_id: String = ""
var curriculum: Dictionary = {}
var maps: Array = []
var sample_words: Array = []
var evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func make_store(label: String) -> RefCounted:
	var store = Store.new()
	store.save_path = "user://learning-"+run_id+"-"+label+".json"
	return store

func write_fixture(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"Fixture writable under isolated profile")
	if file==null: return
	file.store_string(value if value is String else JSON.stringify(value))
	file.flush()
	file.close()

func reopened(store: RefCounted) -> RefCounted:
	var copy = Store.new()
	copy.save_path = store.save_path
	copy.read_save()
	return copy

func answer(store: RefCounted, id: String, skill: String, correct: bool, hinted: bool, context: String, attempt: String, now: float) -> Dictionary:
	var result: Dictionary = store.record_learning(id,skill,correct,hinted,context,attempt,now)
	check(result.has("accepted") and result.has("mastered") and result.has("nextReviewAt"),"Learning answer result contract")
	return result

func run() -> void:
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	var packed: bool = OS.get_cmdline_user_args().has("--packed")
	# Packed res:// may globalize to an empty string; an empty prefix would
	# incorrectly accept every profile, including the player's real one.
	var allowed_root: String = "c:/jp_df/" if packed or workspace.is_empty() else workspace.trim_suffix("/")+"/"
	if not profile.begins_with(allowed_root):
		push_error("Learning QA refuses the real user profile")
		quit(2)
		return
	run_id = Crypto.new().generate_random_bytes(8).hex_encode()
	curriculum = JSON.parse_string(FileAccess.get_file_as_string("res://native/curriculum.json"))
	maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	sample_words = curriculum.basic[0].newWords.slice(0,4).duplicate(true)
	for word in sample_words:
		word.transferExample = {"jp":"ここに"+str(word.jp)+"があります。","reading":"ここに"+str(word.reading)+"があります。","ko":"여기에 "+str(word.ko)+"이/가 있습니다.","parts":[{"text":"ここに"},{"text":word.jp,"reading":word.reading},{"text":"があります。"}]}
	check(sample_words.size()==4 and maps.size()==40,"Real shipped word and map fixtures")
	test_migration()
	test_actual_campaign_migration()
	test_mastery_and_dates()
	test_exposure_context_reload()
	test_receipts_and_recovery()
	test_save_failures()
	test_clock_and_sanitizing()
	test_review_order()
	test_session()
	test_personal_review_budget()
	test_actual_plans()
	test_actual_sentence_routes()
	var report_path: String = "user://qa_learning_progress.json" if packed else "res://tests/qa_learning_progress.json"
	var report: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	check(report!=null,"QA report destination is writable: "+report_path)
	if report!=null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"profile":profile,"evidence":evidence},"  "))
		report.flush()
		var write_error: Error = report.get_error()
		report.close()
		if write_error!=OK: check(false,"QA report could not be completely written")
	print("LEARNING_PROGRESS_QA ",JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)

func test_migration() -> void:
	var id: String = str(sample_words[0].id)
	for version in [1,2]:
		var store = make_store("migration"+str(version))
		var fixture: Dictionary = {"version":version,"maps":{"basic-forest":{"wins":2,"correct":7}},"words":{},"settings":{"music":false,"voice":true}}
		fixture.words[id] = {"seen":50,"correct":40,"wrong":2,"hinted":1,"streak":37}
		if version==2: fixture.army = {"currency":777,"levels":{"archer":4,"spear":2},"selected":"spear"}
		write_fixture(store.save_path,fixture)
		store.read_save()
		check(int(store.data.version)==3,"v"+str(version)+" migrated to version3")
		check(store.data.words[id].streak==37 and store.mastered_count()==0,"Legacy streak is historical, never mastery evidence")
		check(store.data.maps["basic-forest"].wins==2 and not bool(store.data.settings.music),"Map wins and settings preserved")
		var expected: int = 328 if version==1 else 777
		check(int(store.data.army.currency)==expected,"Migration preserves wallet contract")
		check(store.army_level("archer")== (1 if version==1 else 4),"Army training survives migration")
		check(store.write_save(),"Migrated save atomically writes")
		var copy = reopened(store)
		check(int(copy.data.army.currency)==expected and copy.data.words[id].correct==40,"Reload does not grant migration funds twice")
		check(copy.data.learning.items.is_empty(),"No fabricated dates or context evidence from old counters")
	evidence.migrations = "v1/v2 ->3, wallet/army/maps/settings retained, old streak excluded"

func test_actual_campaign_migration() -> void:
	var source: String = "res://tests/profiles/campaign-balance/Godot/app_userdata/말의 전장/campaign-balance-progress.json"
	if not FileAccess.file_exists(source):
		evidence.campaignMigration = {"available":false}
		return
	var original_text: String = FileAccess.get_file_as_string(source)
	var fixture = JSON.parse_string(original_text)
	check(fixture is Dictionary and int(fixture.get("version",0))==2,"Previously completed real campaign is a version2 fixture")
	if not fixture is Dictionary: return
	var store = make_store("real-campaign-migration")
	write_fixture(store.save_path,fixture)
	store.read_save()
	check(store.data.maps==fixture.maps and store.data.maps.size()==40,"All actual40 campaign clear records survive migration")
	check(same_army_values(store.data.army,fixture.army),"Every actual trained army level, selection and wallet is preserved")
	var expected_settings: Dictionary = fixture.settings.duplicate(true)
	if not expected_settings.has("battleMinutes"):
		expected_settings.battleMinutes = 5
	check(store.data.settings==expected_settings and store.data.words==fixture.words,"Actual campaign settings and word history are preserved with the new default duration")
	check(store.unlocked_units().size()==8 and store.mastered_count()==0,"Actual unit unlocks survive without fabricated learning mastery")
	check(store.write_save(),"Actual migrated campaign commits to its separate test profile")
	var copy = reopened(store)
	check(same_army_values(copy.data.army,fixture.army) and copy.data.maps==fixture.maps,"Actual campaign reload does not grant extra funding or lose progress")
	check(FileAccess.get_file_as_string(source)==original_text,"Read-only original campaign fixture remains byte-for-byte intact")
	evidence.campaignMigration = {"available":true,"clears":store.data.maps.size(),"unlocks":store.unlocked_units().size(),"currency":int(store.data.army.currency)}

func same_army_values(actual: Dictionary, expected: Dictionary) -> bool:
	# JSON numbers are floats; valid wallet/levels normalize to ints on load.
	# Compare observable numeric values rather than strict Variant types.
	if float(actual.currency)!=float(expected.currency) or str(actual.selected)!=str(expected.selected): return false
	if actual.levels.size()!=expected.levels.size(): return false
	for id in expected.levels:
		if not actual.levels.has(id) or float(actual.levels[id])!=float(expected.levels[id]): return false
	return true

func test_mastery_and_dates() -> void:
	var id: String = str(sample_words[0].id)
	var store = make_store("mastery")
	store.mark_exposure(id,"meaning","card",T)
	check(store.learning_status(id,"meaning",T).exposures==1 and store.learning_status(id,"meaning",T).correct==0,"Exposure does not imply comprehension")
	for index in range(3):
		check(answer(store,id,"meaning",true,false,"meaning:"+id,"same-day"+str(index),T+index*10).accepted,"Distinct same-day answers persist")
	check(not store.learning_status(id,"meaning",T+100).mastered,"Same-day repetition cannot produce mastery")
	check(store.learning_status(id,"meaning",T+100).statusKo=="시간 두고 복습","Same-day success status explains time boundary")
	check(answer(store,id,"meaning",true,false,"meaning:"+id,"meaning-day2",T+86400).mastered,"Meaning is confirmed on a later date after20h")
	check(store.mastered_count()==0,"Meaning alone is not word mastery")
	for index in range(3):
		answer(store,id,"context",true,false,"example:"+id,"context-same"+str(index),T+86400+index*10)
	check(not store.learning_status(id,"context",T+86500).mastered and store.learning_status(id,"context",T+86500).needsContext,"Repeated identical sentence lacks transfer evidence")
	check(answer(store,id,"context",true,false,"transfer:"+id,"context-transfer",T+172800).mastered,"Second real sentence on a later day confirms context")
	check(store.mastered_count()==1,"Word mastery requires both meaning and transferred context")
	check(not store.learning_status(id,"listening",T+172800).mastered,"Meaning/context does not fabricate listening evidence")
	var copied = reopened(store)
	check(copied.mastered_count()==1 and copied.learning_status(id,"context",T+172800).unhintedCorrect==4,"Mastery evidence and separate counts survive save reload")
	answer(store,id,"meaning",true,true,"meaning:"+id,"hint-after-master",T+172900)
	check(not store.learning_status(id,"meaning",T+172900).mastered and store.mastered_count()==0,"Hint use resets the clean verification sequence")
	check(store.learning_status(id,"meaning",T+172900).hinted==1 and store.learning_status(id,"meaning",T+172900).unhintedCorrect==4,"Lifetime unhinted counts survive a later hint")
	answer(store,id,"meaning",false,false,"meaning:"+id,"wrong-after-hint",T+173000)
	check(store.learning_status(id,"meaning",T+173000).wrong==1 and store.learning_status(id,"meaning",T+173000).nextReviewAt==T+173300,"An error schedules short corrective review")
	var midnight = make_store("midnight")
	for index in range(3): answer(midnight,id,"context",true,false,"example" if index==0 else "transfer","midnight"+str(index),T+86300+index*100)
	check(midnight.learning_status(id,"context",T+86600).successfulDays==2 and not midnight.learning_status(id,"context",T+86600).mastered,"Midnight crossing alone cannot bypass20h evidence")
	evidence.mastery = "3 clean answers, UTC2 dates,20h; context requires2 actual sentence IDs; no mastery from exposure/listening assumptions"

func test_exposure_context_reload() -> void:
	var id: String = str(sample_words[0].id)
	var store = make_store("exposure-context")
	store.mark_exposure(id,"context","stage:basic-forest",T)
	check(store.data.learning.items[id].context.get("lastExposureContext","")=="stage:basic-forest","Exposure stores the actual context identifier")
	check(store.write_save(),"Exposure context atomically commits to the test profile")
	var copy = reopened(store)
	check(copy.data.learning.items[id].context.get("lastExposureContext","")=="stage:basic-forest","Exposure context survives write_save then read_save")
	check(copy.data.learning==store.data.learning,"Exposure reload preserves all skill data rather than silently dropping metadata")
	store.mark_exposure(id,"meaning","",T+1)
	copy = reopened(store)
	check(copy.data.learning.items[id].meaning.has("lastExposureContext") and str(copy.data.learning.items[id].meaning.lastExposureContext).is_empty(),"An explicitly empty exposure context also round-trips")
	var answer_only = make_store("answer-no-exposure")
	answer(answer_only,id,"meaning",true,false,"meaning:"+id,"answer-no-exposure",T)
	var no_exposure = reopened(answer_only)
	check(not no_exposure.data.learning.items[id].meaning.has("lastExposureContext"),"Reload does not invent optional exposure metadata on an answer-only state")
	check(no_exposure.data.learning==answer_only.data.learning,"Answer-only skill data and receipts also round-trip exactly")
	evidence.exposureContexts = "Actual and empty contexts survive save/reload; absent optional keys are not fabricated"

func test_receipts_and_recovery() -> void:
	var id: String = str(sample_words[0].id)
	var store = make_store("receipts")
	check(answer(store,id,"meaning",true,false,"meaning","attempt-fixed",T).accepted,"First receipt accepted")
	var snapshot: Dictionary = store.data.duplicate(true)
	check(not answer(store,id,"meaning",false,true,"other","attempt-fixed",T+86400).accepted and store.data==snapshot,"Replay cannot change answer or evidence")
	var copy = reopened(store)
	check(not answer(copy,id,"meaning",true,false,"meaning","attempt-fixed",T+86400).accepted,"Replay blocked after process reload")
	var batch: Array = [{"itemId":id,"skill":"context","correct":true,"hinted":false,"contextId":"report","attemptId":"fresh-in-batch"},{"itemId":id,"skill":"meaning","correct":true,"hinted":false,"contextId":"meaning","attemptId":"attempt-fixed"}]
	check(not store.record_learning_batch(batch,T+1).accepted and not store.data.learning.attempts.has("fresh-in-batch"),"Partly duplicate batch is rejected atomically")
	write_fixture(store.save_path,"{broken primary")
	var recovered = reopened(store)
	check(not recovered.read_error.is_empty() and recovered.learning_status(id,"meaning",T).correct==1,"Corrupt primary recovers latest committed backup")
	check(not answer(recovered,id,"meaning",true,false,"meaning","attempt-fixed",T+2).accepted,"Recovered latest receipt still rejects replay")
	check(recovered.write_save(),"Recovered state can replace damaged primary with a valid save")
	var broken = make_store("both-broken")
	write_fixture(broken.save_path,"bad")
	write_fixture(broken.save_path+".bak","bad backup")
	broken.read_save()
	check(not broken.read_error.is_empty() and not broken.write_save(),"Unrecoverable corruption is reported without overwriting originals")
	check(FileAccess.get_file_as_string(broken.save_path)=="bad","Corrupt user source is preserved")
	var future = make_store("future-version")
	var future_fixture: Dictionary = future.data.duplicate(true)
	future_fixture.version = 4
	future_fixture.army.currency = 9000
	write_fixture(future.save_path,future_fixture)
	write_fixture(future.save_path+".bak",snapshot)
	future.read_save()
	check(not future.read_error.is_empty() and not future.write_save() and int(JSON.parse_string(FileAccess.get_file_as_string(future.save_path)).version)==4,"A newer save version is preserved instead of downgraded to an old backup")
	write_fixture(store.save_path+".tmp","incomplete temporary write")
	check(reopened(store).learning_status(id,"meaning",T).correct==1,"Uncommitted temporary file is never treated as a save")
	evidence.receipts = "Durable replay rejection, atomic multi-item batch, latest-copy corruption recovery, unreadable copies preserved"

func test_save_failures() -> void:
	var id: String = str(sample_words[0].id)
	var store = make_store("tmp-failure")
	check(store.write_save(),"Save before injected tmp-open failure succeeds")
	var committed: String = FileAccess.get_file_as_string(store.save_path)
	var before: Dictionary = store.data.duplicate(true)
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(store.save_path+".tmp"))==OK,"Create a test directory occupying temporary file path")
	check(not answer(store,id,"meaning",true,false,"meaning","not-committed",T).accepted,"Failed primary write cannot accept/reward an answer")
	check(store.data==before and FileAccess.get_file_as_string(store.save_path)==committed,"Failed write rolls back memory and preserves committed bytes")
	var clear: Dictionary = store.complete_map("basic-forest",{"correct":2})
	check(int(clear.currency)==0 and store.data==before,"Failed campaign save cannot credit army currency")
	store.mark_exposure(id,"meaning","card",T)
	check(store.data==before,"Failed exposure save rolls back exposure")
	store.save_path = "user://learning-"+run_id+"-retry-success.json"
	check(answer(store,id,"meaning",true,false,"meaning","not-committed",T).accepted,"Uncommitted attempt can retry after write destination recovers")
	var rename_failure = make_store("rename-failure")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rename_failure.save_path))==OK,"Create a directory occupying final file destination")
	var rename_before: Dictionary = rename_failure.data.duplicate(true)
	check(not answer(rename_failure,id,"meaning",true,false,"meaning","rename-blocked",T).accepted and rename_failure.data==rename_before,"Atomic rename failure also rolls back transaction")
	var backup_failure = make_store("backup-failure")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_failure.save_path+".bak.tmp"))==OK,"Create a directory occupying backup temporary destination")
	check(answer(backup_failure,id,"meaning",true,false,"meaning","primary-committed",T).accepted,"Backup failure cannot undo an already committed primary receipt")
	check(not backup_failure.save_error.is_empty(),"Secondary-copy failure is explicitly reported")
	check(not answer(reopened(backup_failure),id,"meaning",true,false,"meaning","primary-committed",T+1).accepted,"Committed primary remains replay-safe despite backup failure")
	evidence.atomicSave = "Real filesystem tmp-open and rename failures tested; primary commit determines acceptance; backup warnings never fabricate rollback"

func test_clock_and_sanitizing() -> void:
	var id: String = str(sample_words[0].id)
	var store = make_store("rollback-clock")
	answer(store,id,"context",true,false,"first","clock-first",T+86400)
	answer(store,id,"context",true,false,"second","clock-back",T)
	var status: Dictionary = store.learning_status(id,"context",T)
	check(status.successfulDays==1 and status.nextReviewAt==T+172800,"System clock rollback cannot create an extra date or backward review timestamp")
	check(not answer(store,id,"meaning",true,false,"meaning","nan-clock",NAN).accepted,"Non-finite answer time is rejected")
	check(not answer(store,id,"meaning",true,false,"meaning","infinite-clock",INF).accepted,"Infinite answer time is rejected")
	var corrupt_fields = make_store("field-sanitize")
	var fixture: Dictionary = corrupt_fields.data.duplicate(true)
	fixture.army = {"currency":777,"levels":{"archer":4},"selected":"archer"}
	fixture.words[id] = {"seen":"bad","correct":-8,"streak":123}
	fixture.learning = {"lastClockAt":253402300799,"items":{},"attempts":{}}
	fixture.learning.items[id] = {"context":{"correct":999,"cleanSuccesses":999,"cleanStreak":999,"successfulDates":{"bogus":T},"successfulContexts":{"no-count":0},"firstCleanAt":253402300799,"lastCleanAt":253402300799,"nextReviewAt":253402300799}}
	write_fixture(corrupt_fields.save_path,fixture)
	corrupt_fields.read_save()
	check(corrupt_fields.data.army.currency==777 and corrupt_fields.army_level("archer")==4,"Learning field sanitation preserves valid army")
	check(corrupt_fields.data.words[id].seen==0 and corrupt_fields.data.words[id].correct==0,"Malformed or negative legacy counters sanitized")
	check(not corrupt_fields.learning_status(id,"context").mastered and corrupt_fields.learning_status(id,"context").due,"Malformed future review proof cannot create mastery or lock review")
	evidence.clocks = "UTC midnight,20h separation, rollback, NaN/infinity, damaged far-future timestamps"

func test_review_order() -> void:
	var store = make_store("review")
	var ids: Array = []
	for word in sample_words: ids.append(str(word.id))
	answer(store,str(ids[0]),"meaning",true,false,"meaning","review-good",T)
	answer(store,str(ids[1]),"meaning",true,true,"meaning","review-hint",T+1)
	answer(store,str(ids[2]),"meaning",false,false,"meaning","review-wrong",T+2)
	var ranked: Array = store.review_ids(ids+ids,4,T+3)
	check(ranked.size()==4 and ranked[0]==ids[2] and ranked[1]==ids[1],"Error then hint takes precedence without duplicate review IDs")
	check(store.review_ids(ids,0,T).is_empty(),"Zero review limit has no result")
	check(not "unrelated-locked" in store.review_ids(ids,99,T),"Review is bounded by caller's eligible vocabulary")
	evidence.review = "Wrong/hint priority, overdue timing, caller eligibility, deduplication"

func test_session() -> void:
	var store = make_store("session")
	var fixture_curriculum: Dictionary = {"basic":[{"id":"basic-01","newWords":sample_words,"reviewIds":[]},{"id":"basic-02","newWords":curriculum.basic[1].newWords.slice(0,2),"reviewIds":[str(sample_words[0].id),str(sample_words[1].id)]},{"id":"basic-03","newWords":curriculum.basic[2].newWords.slice(0,2),"reviewIds":[]}]}
	var related: String = str(sample_words[1].id)
	var mission: Dictionary = {"id":"test-river-order","wave":1,"report":{"jp":"川の近くを守れ。","reading":"かわのちかくをまもれ。","ko":"강 근처를 지켜라.","parts":[{"text":"川","reading":"かわ"},{"text":"の近くを守れ。"}]},"targets":[{"id":"left","position":{"x":.2,"y":.5},"label":{"jp":"左","ko":"왼쪽"}},{"id":"right","position":{"x":.6,"y":.5},"label":{"jp":"右","ko":"오른쪽"}}],"answerId":"right","itemIds":[related],"action":{"kind":"support","position":{"x":.6,"y":.5}}}
	var fixture_plans: Dictionary = {"stages":{"basic-forest":{"missions":[mission]}}}
	var session = Session.new()
	session.configure(store,fixture_curriculum,fixture_plans)
	session.rng.seed = 771
	session.begin_lesson(fixture_curriculum.basic[0],{"id":"basic-forest","stageNumber":1})
	check(session.words.size()==4,"All newly introduced words remain in lesson")
	var task: Dictionary = session.next_task([],1,false)
	check(task.kind=="context" and task.itemId==mission.id,"Due mission is prioritized with separate expression item")
	check(session.next_task([],9,true).id==task.id,"Unanswered task survives repeated selection/navigation")
	var changed: Dictionary = task.duplicate(true)
	changed.answerId = "left"
	var wrong: Dictionary = session.record(changed,"left",false)
	check(wrong.accepted and not wrong.correct,"Answer key is internal, never trusted from altered task")
	check(store.learning_status(related,"context").wrong==1 and store.learning_status(mission.id,"context").wrong==1,"Mission records expression and one relevant word atomically")
	check(not session.record(task,"right",false).accepted,"Second submit cannot grant another reward")
	var seen: Array = []
	for word in sample_words: seen.append(str(word.id))
	var previous_id: String = related
	var kinds: Dictionary = {}
	var contexts: Dictionary = {}
	for index in range(30):
		task = session.next_task(seen,2,index>=15)
		check(not task.is_empty() and task.itemId!=previous_id,"Consecutive task repeats are avoided when alternatives exist")
		if task.is_empty(): break
		check(task.kind!="context","One mission does not repeat within a lesson")
		check(index>=15 or task.kind!="listening","Unavailable TTS never creates a listening task")
		kinds[str(task.kind)] = true
		if task.kind=="sentence":
			check(task.skill=="context" and task.item.jp!=word_for_id(str(task.itemId)).jp,"Sentence task uses actual sentence rather than isolated word")
			var correct_sentence: String = str(task.item.ko)
			for choice in task.choices:
				if choice.id==task.answerId: check(choice.label==correct_sentence,"Sentence answer label is full Korean sentence")
			contexts[str(task.contextId)] = true
		var result: Dictionary = session.record(task,str(task.answerId),false)
		check(result.accepted and result.correct and result.has("mastered") and result.has("nextReviewAt"),"UI answer/result contract and durable acceptance")
		previous_id = str(task.itemId)
	check(kinds.has("meaning") and kinds.has("sentence") and kinds.has("listening"),"Meaning, sentence and real-voice listening alternate")
	var has_transfer: bool = false
	for context in contexts: has_transfer = has_transfer or str(context).begins_with("transfer:")
	check(has_transfer,"Transfer sentence is practiced rather than synthetic wave context")
	store.data.words[str(curriculum.basic[2].newWords[0].id)] = {"seen":1}
	var replay = Session.new()
	replay.configure(store,fixture_curriculum,{})
	replay.begin_lesson(fixture_curriculum.basic[1],{"id":"basic-farm","stageNumber":2})
	var included: Array = []
	for word in replay.words: included.append(str(word.id))
	check(str(fixture_curriculum.basic[1].newWords[0].id) in included and str(fixture_curriculum.basic[1].newWords[1].id) in included,"Personal review preserves the entire new-word set")
	check(related in included,"Reached prior weak word joins personal review")
	check(not str(curriculum.basic[2].newWords[0].id) in included,"Later locked new vocabulary is excluded even if an old record names it")
	var failure_store = make_store("session-save-failure")
	var blocked_session = Session.new()
	blocked_session.configure(failure_store,fixture_curriculum,{})
	blocked_session.begin_lesson(fixture_curriculum.basic[0],{"id":"basic-forest","stageNumber":1})
	var pending_task: Dictionary = blocked_session.next_task(seen,1,false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(failure_store.save_path+".tmp"))
	check(not blocked_session.record(pending_task,str(pending_task.answerId),true).accepted,"Session does not reward uncommitted answer")
	check(blocked_session.next_task(seen,3,true).id==pending_task.id,"Save failure leaves the same task pending")
	failure_store.save_path = "user://learning-"+run_id+"-session-retry.json"
	check(blocked_session.record(pending_task,str(pending_task.answerId),false).accepted and failure_store.learning_status(str(pending_task.itemId),"meaning").hinted==1,"Retry cannot erase hint evidence even if caller resets hinted flag")
	var skipped = Session.new()
	var skip_store = make_store("skip")
	skipped.configure(skip_store,fixture_curriculum,fixture_plans)
	skipped.begin_lesson(fixture_curriculum.basic[0],{"id":"basic-forest","stageNumber":1})
	var skip_task: Dictionary = skipped.next_task(seen,1,false)
	skipped.set_hinted(str(skip_task.id))
	skipped.skip_task(skip_task)
	check(skip_store.learning_status(mission.id,"context").correct==0 and skip_store.learning_status(mission.id,"context").wrong==0 and skip_store.learning_status(mission.id,"context").exposures==1,"Skip records exposure without success/error/mastery credit")
	check(not skipped.record(skip_task,str(skip_task.answerId),false).accepted,"Skipped task cannot later submit for rewards")
	var after_skip: Dictionary = skipped.next_task(seen,2,false)
	check(after_skip.id!=skip_task.id and after_skip.kind!="context","Skipping consumes mission and gives a new wave task")
	skipped.set_hinted(str(after_skip.id))
	var hinted_result: Dictionary = skipped.record(after_skip,str(after_skip.answerId),false)
	check(hinted_result.accepted and hinted_result.hinted and skip_store.learning_status(str(after_skip.itemId),str(after_skip.skill)).hinted==1,"Explicit hint API remains sticky over caller/UI state reset")
	evidence.session = {"kinds":kinds.keys(),"sentenceContexts":contexts.size(),"pendingStable":true,"futureVocabularyExcluded":true,"missionRepresentativeWords":1}

func test_personal_review_budget() -> void:
	var all_lessons: Array = []
	for tier in ["basic","beginner","intermediate","advanced"]:
		all_lessons.append_array(curriculum.get(tier,[]))
	var observed: Array = []
	for lesson_index in [1,10,20,30]:
		var store = make_store("budget"+str(lesson_index))
		var current: Dictionary = all_lessons[lesson_index]
		var previous: Array = []
		for index in range(lesson_index):
			for word in all_lessons[index].newWords: previous.append(str(word.id))
		var unseen: String = str(previous[0])
		for id in previous:
			if id!=unseen: store.data.words[id] = {"seen":1}
		# Reaching even the final map does not make unexposed words eligible.
		store.data.maps[str(maps[-1].id)] = {"wins":1}
		var future: String = str(all_lessons[lesson_index+1].newWords[0].id)
		store.data.words[future] = {"seen":1}
		var wrong_id: String = str(previous[-1])
		for id in previous:
			if id!=unseen and not id in current.reviewIds:
				wrong_id = str(id)
				break
		var hint_id: String = str(previous[-2]) if str(previous[-2])!=wrong_id else str(previous[-3])
		answer(store,wrong_id,"context",false,false,"example:"+wrong_id,"budget-wrong",T)
		answer(store,hint_id,"meaning",true,true,"meaning:"+hint_id,"budget-hint",T+1)
		var exposure_id: String = str(previous[-4])
		store.mark_exposure(exposure_id,"listening","heard",T+2)
		store.data.words.erase(exposure_id)
		var session = Session.new()
		session.configure(store,curriculum,{})
		session.begin_lesson(current,maps[lesson_index])
		var review: Array = []
		var new_ids: Array = []
		var actual_ids: Array = []
		for word in current.newWords: new_ids.append(str(word.id))
		for word in session.words:
			actual_ids.append(str(word.id))
			if not str(word.id) in new_ids: review.append(str(word.id))
		var expected: int = mini(current.reviewIds.size(),previous.size()-1)
		check(review.size()==expected,"Actual lesson reviewIds supplies the personal review budget: "+str(current.id))
		check(session.words.size()==current.newWords.size()+expected,"New vocabulary count remains intact: "+str(current.id))
		check(review.size()>=2 and review[0]==wrong_id and review[1]==hint_id,"Personal errors/hints lead instead of the fixed authored IDs: "+str(current.id))
		check(not unseen in review and not future in review,"Unexposed reached vocabulary and later vocabulary stay out: "+str(current.id))
		check(exposure_id in review,"Learning exposure is sufficient without an old seen counter: "+str(current.id))
		for word in current.newWords:
			check(str(word.id) in actual_ids and not str(word.id) in review,"Current-map words remain introductions, never duplicate review")
		observed.append({"lesson":str(current.id),"budget":current.reviewIds.size(),"review":review.size(),"new":current.newWords.size()})
	var fresh = make_store("budget-fresh")
	var first = Session.new()
	first.configure(fresh,curriculum,{})
	first.begin_lesson(all_lessons[0],maps[0])
	check(first.words.size()==all_lessons[0].newWords.size(),"First Basic lesson keeps its zero-review budget")
	evidence.personalReview = observed

func word_for_id(id: String) -> Dictionary:
	for word in sample_words:
		if str(word.id)==id: return word
	return {}

func test_actual_plans() -> void:
	if not FileAccess.file_exists("res://native/learning_plans.json"):
		evidence.actualPlans = {"available":false}
		return
	var actual_plans = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	check(actual_plans is Dictionary and actual_plans.get("stages") is Dictionary,"Actual learning plans are parseable")
	if not actual_plans is Dictionary or not actual_plans.get("stages") is Dictionary: return
	var lessons: Dictionary = {}
	var transfer_count: int = 0
	var word_count: int = 0
	for tier in ["basic","beginner","intermediate","advanced"]:
		for lesson in curriculum.get(tier,[]):
			lessons[str(lesson.id)] = lesson
			for word in lesson.newWords:
				word_count += 1
				if word.get("transferExample") is Dictionary and str(word.transferExample.get("jp",""))!=str(word.example.jp): transfer_count += 1
	var store = make_store("actual120")
	var session = Session.new()
	session.configure(store,curriculum,actual_plans)
	var mission_count: int = 0
	var related_count: int = 0
	var stage_count: int = 0
	for stage in maps:
		var plan: Dictionary = actual_plans.stages.get(str(stage.id),{})
		check(not plan.is_empty() and lessons.has(str(plan.get("lessonId",""))),str(stage.id)+": actual plan maps to a real lesson")
		if plan.is_empty() or not lessons.has(str(plan.get("lessonId",""))): continue
		stage_count += 1
		session.begin_lesson(lessons[str(plan.lessonId)],stage)
		for mission in plan.get("missions",[]):
			var task: Dictionary = session.next_task([],int(mission.wave),false)
			check(not task.is_empty() and task.kind=="context" and task.itemId==str(mission.id),str(stage.id)+": actual due mission issues exactly once")
			if task.is_empty(): continue
			check(task.item.jp==str(mission.report.jp),str(stage.id)+": actual report is the task prompt")
			var result: Dictionary = session.record(task,str(mission.answerId),false)
			check(result.accepted and result.correct,str(stage.id)+": actual spatial target answer is accepted once")
			check(not session.record(task,str(mission.answerId),false).accepted,str(stage.id)+": actual mission reward is replay-safe")
			mission_count += 1
			if not str(task.get("representativeItemId","")).is_empty():
				related_count += 1
				check(session.word_index.has(str(task.representativeItemId)) and int(session.word_index[str(task.representativeItemId)].lessonNumber)<=session.maximum_reached,str(stage.id)+": representative vocabulary is real and reached")
	check(stage_count==40 and mission_count==120,"All40 maps issue all120 actual learning missions")
	check(store.mastered_count()==0,"Same-day mission bulk cannot manufacture word mastery")
	check(store.data.maps.is_empty() and store.data.army.currency==180 and store.army_level("archer")==1,"Learning QA cannot change campaign, wallet or training")
	evidence.actualPlans = {"available":true,"stages":stage_count,"missions":mission_count,"representativeWordMissions":related_count,"words":word_count,"transferExamplesCurrentlyAvailable":transfer_count}

func test_actual_sentence_routes() -> void:
	var store = make_store("actual900-sentences")
	var session = Session.new()
	session.configure(store,curriculum,{})
	var word_count: int = 0
	var task_count: int = 0
	var lesson_count: int = 0
	for tier in ["basic","beginner","intermediate","advanced"]:
		for lesson in curriculum.get(tier,[]):
			session.begin_lesson(lesson,maps[lesson_count])
			lesson_count += 1
			for original in lesson.newWords:
				var id: String = str(original.id)
				var word: Dictionary = session.word_index[id]
				var alternate = word.get("transferExample")
				check(alternate is Dictionary and not str(alternate.get("jp","")).is_empty() and not str(alternate.get("ko","")).is_empty(),id+": actual transfer sentence is available")
				if not alternate is Dictionary: continue
				check(str(alternate.jp)!=str(word.example.jp),id+": transfer is a different Japanese context")
				# Exercise the actual sentence-selection/choice path for every word;
				# full public answer transactions are tested separately per lesson.
				var first: Dictionary = session._sentence(word)
				var second: Dictionary = session._sentence(word)
				check(first.jp==str(word.example.jp) and second.jp==str(alternate.jp),id+": original and transfer alternate without synthetic contexts")
				check(first.contextId=="example:"+id and second.contextId=="transfer:"+id,id+": two authored contexts retain distinct evidence IDs")
				for item in [first,second]:
					var choices: Array = session._choices(word,item,"sentence")
					var labels: Dictionary = {}
					var correct_count: int = 0
					for choice in choices:
						labels[str(choice.label)] = true
						if str(choice.id)==id and str(choice.label)==str(item.ko): correct_count += 1
					check(choices.size()>=2 and labels.size()==choices.size() and correct_count==1,id+": full Korean sentence has one valid answer and distinct distractors")
				word_count += 1
			var representative: String = str(lesson.newWords[0].id)
			var issued_contexts: Array = []
			for index in range(3):
				var task: Dictionary = session.next_task([representative],index+1,false)
				check(not task.is_empty() and task.itemId==representative,str(lesson.id)+": public task selection stays inside the actually seen word")
				if task.is_empty(): continue
				check(task.kind==("meaning" if index==0 else "sentence"),str(lesson.id)+": public no-voice lesson alternates meaning and real sentences")
				if index>0: issued_contexts.append(str(task.contextId))
				var result: Dictionary = session.record(task,str(task.answerId),false)
				check(result.accepted and result.correct,str(lesson.id)+": actual sentence answer durably commits once")
				check(not session.record(task,str(task.answerId),false).accepted,str(lesson.id)+": actual sentence receipt cannot be replayed")
				task_count += 1
			check(issued_contexts==["example:"+representative,"transfer:"+representative],str(lesson.id)+": full public flow practices both actual authored contexts")
	check(word_count==900 and lesson_count==40 and task_count==120,"All900 word sentence paths and40 public lesson flows are exercised")
	check(store.mastered_count()==0,"Same-day full-content run never becomes vocabulary mastery")
	check(store.data.maps.is_empty() and int(store.data.army.currency)==180,"Actual sentence verification cannot change campaign funding")
	evidence.sentenceRoutes = {"words":word_count,"lessons":lesson_count,"publicTasks":task_count,"differentAuthoredContexts":true,"voiceUnavailableNeverListening":true}
