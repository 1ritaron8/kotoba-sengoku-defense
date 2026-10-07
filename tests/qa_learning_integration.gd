extends SceneTree
## Real app UI, issued session tasks, save receipts and battlefield actions.
## Wave completion is driven directly here; combat itself is verified by the
## separate all/mixed/none campaign simulations and live projectile tests.
var checks: int = 0
var failures: Array = []
var app: Node
var observations: Array = []
var captured: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func settle_learning() -> void:
	# Timing/input gates are verified separately by qa_learning_transition.
	# This matrix advances the real controller to test all authored tasks.
	for unused in range(12):
		if not app.learning_transition.is_busy(): break
		if DisplayServer.get_name()=="headless" and app.learning_transition.animation!=null and app.learning_transition.animation.is_valid():
			app.learning_transition.animation.custom_step(1.0)
		await process_frame
	check(not app.learning_transition.is_busy(),"Learning task reaches its input-ready presentation")

func answer_current(correct: bool) -> void:
	var answer: String = str(app.quiz_task.answerId)
	if not correct:
		for choice in app.quiz_task.choices:
			if str(choice.id)!=answer:
				answer = str(choice.id)
				break
	if app.context_task_active:
		app._answer_context(answer)
	else:
		app._answer_quiz(answer)

func capture(path: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error: int = root.get_texture().get_image().save_png(path)
	check(error==OK,"Actual GPU learning UI capture is saved: "+path)

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/"):
		push_error("Learning app QA refuses the player's profile")
		quit(2)
		return
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://learning-integration-%d.json" % Time.get_ticks_msec()
	root.add_child(app)
	await process_frame
	app.progress.data.settings.voice = false
	app.progress.data.settings.music = false
	app.player.stop()
	check(app.progress.data.words.is_empty() and app.progress.data.learning.items.is_empty(),"Hidden startup preview does not record learning exposure")
	check(app.learning_plans.stages.size()==40,"Installed UI loads a lesson goal for every campaign map")
	check(app.words_by_id.size()==900,"All nine hundred authored words load in the learning app")
	for word in app.words_by_id.values():
		check(word.get("transferExample") is Dictionary and str(word.transferExample.get("jp",""))!=str(word.example.jp),"Every word has a distinct second authored sentence: "+str(word.id))
	var starter_profile: Dictionary = app.progress.data.army.duplicate(true)
	for tier in range(4):
		app._select_tier(tier)
		for stage_index in range(10):
			var before_preview: Dictionary = app.progress.data.learning.duplicate(true)
			var before_words: Dictionary = app.progress.data.words.duplicate(true)
			app._select_map(stage_index)
			await process_frame
			var stage_id: String = str(app.current_map.id)
			check(str(app.stage_learning.lessonId)==str(app.current_lesson.id),"Map opens its own authored learning plan: "+stage_id)
			check(not str(app.stage_learning.goalKo).is_empty(),"Map briefing explains its learning goal: "+stage_id)
			check(app.quiz_task.is_empty() and not app.context_task_active,"Map change clears the former UI task: "+stage_id)
			check(app.progress.data.learning==before_preview and app.progress.data.words==before_words,"Map preview cannot add exposure to unseen vocabulary: "+stage_id)
			app._begin_battle()
			check(str(app.learning_words[app.learning_index].id) in app.seen_this_run,"Starting battle records the word actually displayed: "+stage_id)
			app.game.set_process(false)
			check(not app.learning_field.mission.is_empty() and app.learning_field.report_text.meaning_visible,"A real wave-start event displays its report with translation: "+stage_id)
			var results: Array = []
			for wave in range(1,7):
				for index in range(4): app._advance_word()
				# This matrix isolates the real UI at a completed time window.
				# Actual clock/combat progression is exercised by duration QA.
				if app.game._is_timed_battle():
					app.game.elapsed = float(app.game._timed_wave().endSeconds)
				app.game._complete_wave()
				await process_frame
				await settle_learning()
				var task: Dictionary = app.quiz_task.duplicate(true)
				check(not task.is_empty(),"A completed wave offers an issued learning task")
				check(str(task.kind)!="listening","Voice-off preference does not issue automatic listening tasks")
				var is_context: bool = str(task.kind)=="context"
				if wave in [1,3,6]:
					check(is_context and int(task.mission.wave)==wave,"The taught report becomes a location choice at its own wave")
					check(app.context_task_active and app.modal==null and not app.game.input_enabled,"Location choice consumes battlefield input without a quiz modal")
					check(not app.learning_field.report_text.meaning_visible,"The test asks for Japanese comprehension before a translation hint")
					check(not app.hint_bar.visible,"Old battlefield footer cannot cover learning choice actions")
				else:
					check(app.modal!=null and not app.context_task_active,"Word and sentence tasks use the readable modal")
					check(app.modal_footer!=null,"Hint/listen/skip actions remain in the fixed modal footer")
					check(app.modal_footer.get_global_rect().end.y<=app.modal_card.get_global_rect().end.y,"Fixed quiz actions remain inside the card")
				var hinted: bool = false
				if tier==0 and stage_index==0 and wave==1:
					app._quiz_hint()
					hinted = true
					check(app.learning_field.report_text.meaning_visible,"Hint reveals the actual report translation")
					app._show_study()
					check(app.modal_context=="study" and not app.learning_field.visible,"Dictionary inspection suspends location choice UI")
					app._return_from_study()
					await settle_learning()
					check(str(app.quiz_task.id)==str(task.id) and app.quiz_hinted,"Dictionary return preserves the same task and its help usage")
					app._show_catalog()
					app._resume_from_navigation()
					await settle_learning()
					check(str(app.quiz_task.id)==str(task.id) and app.quiz_hinted,"Navigation preserves hinted evidence")
					await capture("C:/JP_DF/dist/preview-learning-context.png")
				if tier==0 and stage_index==0 and wave==2:
					app._show_study()
					app._return_from_study()
					await settle_learning()
					hinted = true
					check(app.quiz_hinted,"Looking up a pending answer in the dictionary counts as assistance")
				if tier==0 and stage_index==0 and wave==3:
					app._quiz_hint()
					app._continue_battle()
					await settle_learning()
					check(app.lesson_session.pending.is_empty(),"Skipping consumes the pending task and prevents hinted reissue")
					results.append({"wave":wave,"kind":task.kind,"skipped":true})
					continue
				var correct: bool = wave!=4
				var gold: int = app.game.gold
				var supports: int = app.game.battle_support.claims.size()
				answer_current(correct)
				await settle_learning()
				check(app.quiz_resolved,"A valid answer receives a persistent transaction receipt")
				check(app.game.gold==gold,"Approved random battle support replaces the old correct-answer cash")
				check(app.game.battle_support.claims.size()==supports+(1 if correct else 0),"Only an accepted correct answer earns one support")
				if correct:
					var earned: Dictionary=app.game.battle_support.claims[str(task.id)]
					check(earned.hinted==hinted and earned.state=="queued","Result records actual help and defers support until battle return")
				if is_context and correct:
					var aura: Dictionary = app.game.battle_support.claims[str(task.id)]
					var location: Dictionary = task.mission.action.position
					location=app.game.config.get("historicalBattlefield",{}).get("learningSupportAnchors",{}).get(str(task.mission.id),location)
					check(Vector2(float(aura.requestedAnchor.x),float(aura.requestedAnchor.y)).distance_to(Vector2(float(location.x),float(location.y)))<0.0001,"Support binds to the unchanged real report anchor")
				var reward_gold: int = app.game.gold
				var earned_supports: int = app.game.battle_support.claims.size()
				answer_current(true)
				check(app.game.gold==reward_gold and app.game.battle_support.claims.size()==earned_supports,"Re-answering cannot duplicate or reroll support")
				if tier==0 and stage_index==0 and wave==1:
					app._show_study()
					app._return_from_study()
					await settle_learning()
					check(app.quiz_resolved and app.learning_field.resolved,"Resolved location tasks return as results rather than a fresh test")
					check(app.game.gold==reward_gold,"Dictionary return cannot re-credit the reward")
					await capture("C:/JP_DF/dist/preview-learning-support.png")
				if tier==3 and stage_index==7 and is_context and wave==3:
					await capture("C:/JP_DF/dist/preview-learning-advanced.png")
				results.append({"wave":wave,"kind":task.kind,"correct":correct,"hinted":hinted})
				app._continue_battle()
				await settle_learning()
				check(app.quiz_task.is_empty() and not app.context_task_active and app.game.input_enabled,"Next battle resumes input and closes only the completed task")
			observations.append({"stageId":stage_id,"goal":app.stage_learning.goalKo,"tasks":results})
	check(app.progress.data.army==starter_profile,"Learning alone does not spend or change persistent army funds")
	check(app.progress.mastered_count()==0,"Same-day campaign UI answers never manufacture long-term mastery")
	var saved_words: Dictionary = app.progress.data.words.duplicate(true)
	var saved_learning: Dictionary = app.progress.data.learning.duplicate(true)
	app.progress.read_save()
	check(app.progress.data.words==saved_words,"Actual learning word history survives reload")
	check(app.progress.data.learning==saved_learning,"Skill records and reward receipts survive reload")
	var report: Dictionary = {"checks":checks,"failures":failures,"stages":observations,"scope":"Actual app task, help, navigation, dictionary, fixed actions, local support, skip and save paths. Wave completion is driven for UI; combat is separately simulated."}
	var out: FileAccess = FileAccess.open("user://qa_learning_integration.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	out.close()
	print("LEARNING_APP ",checks," checks / ",failures.size()," failures / ",observations.size()," maps; report=",ProjectSettings.globalize_path("user://qa_learning_integration.json"))
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	await create_timer(0.5).timeout
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
