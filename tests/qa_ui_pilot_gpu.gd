extends SceneTree
## Actual Stage 01 Main input and GPU frames in an isolated starter profile.
## Catalog prewarm is explicitly skipped; simulation/learning/rendering are live.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var captures: Array = []
var orders: Array = []
var learning_actions: Array = []
var menu_actions: Array = []
var motion_samples: Array = []
var contact_samples: Array = []
var enemy_tracks: Dictionary = {}
var finished: bool = false
var started_usec: int = 0
var initial_source_hashes: Dictionary = {}
const SOURCE_FILES: Array = ["native/main.gd","native/game.gd","native/troops_3d.gd","native/deployment_drag_overlay.gd","native/battlefield_hud.gd","native/sengoku_ui.gd","native/maps.json","assets/battlefields-rendered/manifest.json"]

class PilotMain extends "res://native/main.gd":
	func _prepare_catalog_previews() -> void:
		# This harness verifies the current first battlefield, not all forty
		# catalog previews or preparation latency. No battle process is altered.
		catalog_preparation_started = true
		catalog_preparation_ready = true
		front_end.set_catalog_preparation(maps.size(),maps.size())

func _initialize() -> void:
	print("UI_PILOT_GPU_INITIALIZE")
	call_deferred("run")

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in SOURCE_FILES: result[path] = FileAccess.get_sha256("res://" + str(path))
	return result

func check(value: bool, note: String) -> bool:
	checks += 1
	if not value:
		failures.append(note)
		if failures.size() <= 20: push_error("UI_PILOT_GPU " + note)
	return value

func canonical(path: String) -> String:
	return path.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

func guarded_profile() -> bool:
	var allowed: String = canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	var local: String = canonical(OS.get_environment("LOCALAPPDATA"))
	var user_path: String = canonical(ProjectSettings.globalize_path("user://"))
	return check(DisplayServer.get_name() != "headless" and roaming.is_absolute_path() and roaming.begins_with(allowed + "/ui-pilot-gpu") and local == roaming and user_path.begins_with(roaming + "/"), "GPU harness refuses every profile outside isolated ui-pilot-gpu* runs")

func settle(frames: int = 3) -> void:
	for frame in range(frames): await process_frame

func motion(position_value: Vector2, held: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position_value
	event.global_position = position_value
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	await process_frame

func mouse(position_value: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position_value
	event.global_position = position_value
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func click(control: Control) -> void:
	var position_value: Vector2 = control.get_global_rect().get_center()
	await motion(position_value)
	await mouse(position_value,true)
	await mouse(position_value,false)

func touch_click(control: Control) -> void:
	for pressed in [true,false]:
		var event: InputEventScreenTouch = InputEventScreenTouch.new()
		event.index = 0
		event.position = control.get_global_rect().get_center()
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func verify_menu(input_kind: String) -> void:
	if input_kind == "touch": await touch_click(app.battle_menu_button)
	else: await click(app.battle_menu_button)
	await settle()
	var opened: bool = app.modal_context == "pause" and app.modal != null and app.game.paused and not app.game.input_enabled
	check(opened,"Actual GPU " + input_kind + " menu input opens the pause modal and locks battlefield orders")
	menu_actions.append({"input":input_kind,"action":"open-pause-menu","opened":opened,"modalContext":app.modal_context,"paused":app.game.paused,"inputEnabled":app.game.input_enabled})
	if not opened: return
	await capture(str(root.size.x) + "x" + str(root.size.y) + "-" + input_kind + "-pause-menu")
	var resume: Button
	for control in app.modal_body.find_children("*","Button",true,false):
		if control.text.contains("전투 계속"):
			resume = control
			break
	if check(resume != null,"Actual pause menu contains its production resume button"):
		await click(resume)
	else:
		app._close_modal(true)
		menu_actions.append({"input":"callback-fallback","action":"close-pause-menu","reason":"Production resume button was not found; validation already failed."})
	await settle()
	var resumed: bool = app.modal == null and app.modal_context.is_empty() and not app.game.paused and app.game.input_enabled
	check(resumed,"Actual GPU menu resume button restores normal battle input and processing")
	menu_actions.append({"input":"mouse","action":"resume-button","resumed":resumed})

func resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	app._layout()
	await settle()
	for control in [app.hud_gold,app.hud_capacity,app.hud_health,app.hud_wave,app.pause_button,app.speed_button,app.battle_menu_button]:
		check(root.get_visible_rect().encloses(control.get_global_rect()),"GPU HUD geometry fits " + str(dimensions) + ": " + str(control.name))

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var path: String = "user://ui-pilot-" + label + ".png"
	if check(pixels != null and not pixels.is_empty(),"Root GPU framebuffer exists for " + label):
		check(pixels.get_size() == root.size,"Framebuffer uses requested viewport size for " + label)
		check(pixels.save_png(path) == OK,"GPU screenshot saves for " + label)
		captures.append({"label":label,"path":ProjectSettings.globalize_path(path),"width":pixels.get_width(),"height":pixels.get_height(),"elapsed":app.game.elapsed,"wave":app.game.wave,"enemies":app.game.enemies.size(),"units":app.game.units.size(),"queued":app.game.recruitment_queue.size(),"learningPhase":app.learning_transition.phase})

func begin_drag(id: String) -> bool:
	var card: Button = app.army_grid.get_node_or_null("DeployCard_" + id) as Button
	if not check(card != null and not card.disabled,"GPU native roster card permits " + id): return false
	var center: Vector2 = card.get_global_rect().get_center()
	var recruits_before: int = app.game.recruits
	var jobs_before: int = app.game.next_recruitment_id
	await motion(center)
	await mouse(center,true)
	await motion(center + Vector2(12,-24),true)
	return check(not app.deployment_drag.is_empty() and app.game.recruits == recruits_before and app.game.next_recruitment_id == jobs_before,"Actual held GPU pointer starts a free " + id + " drag without accepting an order")

func target(id: String) -> Vector2:
	if str(app.game.placement_contract(id).deploymentKind) == "marching":
		var base: Dictionary = app.game.ground_combat.select_march_base()
		return app.game.field_point_to_screen(base.position) if not base.is_empty() else Vector2(-1,-1)
	for zone in app.game.zones:
		var candidate: Vector2 = app.game._zone_placement_hint(zone,id)
		if candidate.x < 0 or not bool(app.game.deployment_preview(id,candidate).get("valid",false)): continue
		var projected: Vector2 = app.game.field_point_to_screen(candidate)
		if not app._deployment_surface_point(projected).is_empty(): return projected
	return Vector2(-1,-1)

func hover_and_capture(id: String, dimensions: Vector2i) -> Vector2:
	await resize(dimensions)
	var destination: Vector2 = target(id)
	check(destination.x >= 0,"Actual existing Stage 01 supplies an accessible " + id + " target at " + str(dimensions))
	await motion(destination,true)
	await settle()
	var preview: Dictionary = app.deployment_drag.get("preview",{})
	check(bool(preview.get("valid",false)) and bool(preview.get("visible",false)),"GPU drag uses a valid visible current " + id + " preview at " + str(dimensions))
	var ghost: Node3D = app.troops_3d.placement_actor
	check(is_instance_valid(ghost) and ghost.visible and ghost.unit_type == id,"Actual class-specific GPU preview actor is visible for " + id)
	await capture(str(dimensions.x) + "x" + str(dimensions.y) + "-" + id + "-ghost")
	return destination

func drop(id: String, destination: Vector2) -> void:
	var recruits_before: int = app.game.recruits
	var order_id: int = app.game.next_recruitment_id
	var orders_before: int = orders.size()
	await mouse(destination,false)
	await settle()
	check(app.deployment_drag.is_empty() and not app.deployment_release_pending and not app.game.ui_deployment_active,"GPU " + id + " release clears gesture ownership and ghost state")
	check(app.game.recruits == recruits_before + 1 and app.game.next_recruitment_id == order_id + 1 and orders.size() == orders_before + 1,"GPU " + id + " drop accepts exactly one real paid production order")
	if orders.size() > orders_before:
		check(int(orders.back().get("cost",0)) == app.game.recruit_cost(id),"GPU " + id + " order reports its existing price")
	await mouse(destination,false)
	check(app.game.recruits == recruits_before + 1 and app.game.next_recruitment_id == order_id + 1,"Duplicate pointer release creates no second GPU order")

func answer_learning() -> void:
	if app.quiz_task.is_empty() or not app.learning_transition.accepts_actions(): return
	var task_id: String = str(app.quiz_task.get("id",""))
	if not app.quiz_resolved:
		var buttons: Array = app.learning_field.target_buttons if app.context_task_active else app.quiz_choices
		var choices: Array = app.quiz_task.get("mission",{}).get("targets",[]) if app.context_task_active else app.quiz_task.get("choices",[])
		var answer: String = str(app.quiz_task.get("mission",{}).get("answerId","")) if app.context_task_active else str(app.quiz_task.get("answerId",""))
		for index in range(mini(buttons.size(),choices.size())):
			var button: Button = buttons[index]
			if str(choices[index].get("id","")) == answer and button.is_visible_in_tree() and not button.disabled:
				await capture("learning-" + str(learning_actions.size()) + "-choice")
				await click(button)
				learning_actions.append({"taskId":task_id,"action":"actual-pointer-correct-choice","answerId":answer,"resolved":app.quiz_resolved,"wallSeconds":float(Time.get_ticks_usec()-started_usec)/1000000.0})
				return
	else:
		var button: Button = app.learning_field.continue_button if app.context_task_active else app.quiz_continue_button
		if button != null and button.is_visible_in_tree() and not button.disabled:
			await click(button)
			learning_actions.append({"taskId":task_id,"action":"actual-pointer-return-to-battle","wallSeconds":float(Time.get_ticks_usec()-started_usec)/1000000.0})

func vector_record(value: Vector3) -> Dictionary:
	return {"x":value.x,"y":value.y,"z":value.z}

func sample_natural_motion() -> void:
	var records: Array = []
	for enemy in app.game.enemies:
		var id: String = str(enemy.id)
		var position_value: Vector2 = enemy.position
		if not enemy_tracks.has(id): enemy_tracks[id] = {"first":position_value,"last":position_value,"distance":0.0,"samples":0}
		var track: Dictionary = enemy_tracks[id]
		track.distance = float(track.distance) + position_value.distance_to(track.last)
		track.last = position_value
		track.samples = int(track.samples) + 1
		if records.size() < 6: records.append({"id":enemy.id,"position":{"x":position_value.x,"y":position_value.y},"animation":enemy.animation,"pathIndex":enemy.pathIndex})
	motion_samples.append({"elapsed":app.game.elapsed,"wave":app.game.wave,"paused":app.game.paused,"betweenWaves":app.game.between_waves,"enemies":app.game.enemies.size(),"units":app.game.units.size(),"sampledEnemies":records})
	var sampled: int = 0
	for key in app.troops_3d.actors:
		var actor: Node3D = app.troops_3d.actors[key]
		if str(actor.current_state.get("animation","")) != "walk": continue
		var sole_minimum: Dictionary = {}
		for suffix in ["L","R"]:
			var foot: Node3D = actor.bones.get("foot" + suffix)
			if foot == null: continue
			var minimum: float = INF
			for mesh in actor.meshes:
				if mesh.get_parent() != foot: continue
				for surface in range(mesh.mesh.get_surface_count()):
					for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						var world_vertex: Vector3 = mesh.global_transform * vertex
						minimum = minf(minimum,world_vertex.y-app.troops_3d._ground_contact_height(world_vertex))
			if is_finite(minimum): sole_minimum[suffix] = minimum
		contact_samples.append({"actorKey":key,"type":actor.unit_type,"hostile":actor.hostile,"elapsed":app.game.elapsed,"root":vector_record(actor.global_position),"rootGroundHeight":app.troops_3d._ground_contact_height(actor.global_position),"sourceFootMeshMinClearance":sole_minimum,"locomotionPhase":actor.current_state.get("locomotionPhase",0),"groundContactEvidence":"Live posed source-foot geometry and terrain sampler; does not prove final skinned pixel contact."})
		sampled += 1
		if sampled >= 3: break

func finish() -> void:
	if finished: return
	finished = true
	var moving: int = 0
	for track in enemy_tracks.values():
		if float(track.distance) > .001 and int(track.samples) > 1: moving += 1
	check(moving > 0,"Regular process frames move naturally spawned enemy IDs through authored routes")
	check(not motion_samples.is_empty() and not contact_samples.is_empty(),"Natural live battle records movement and terrain-contact diagnostics")
	check(app.progress.unlocked_units() == ["archer","spear"] and app.progress.data.maps.is_empty(),"GPU starter profile keeps actual unlocks and fabricates no campaign clear")
	var final_source_hashes: Dictionary = source_hashes()
	var report: Dictionary = {"checks":checks,"failures":failures,"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"catalogPrewarmSkipped":true,"initialSourceHashes":initial_source_hashes,"finalSourceHashes":final_source_hashes,"sourceFrozenDuringHarness":initial_source_hashes == final_source_hashes,"captures":captures,"acceptedOrders":orders,"menuActions":menu_actions,"learningActions":learning_actions,"motionSamples":motion_samples,"contactSamples":contact_samples,"naturallyMovingEnemyIds":moving,"wallSeconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"simulationElapsed":app.game.elapsed,"finalWave":app.game.wave,"finishedBattle":app.game.finished,"scope":"Actual production Main subclass overrides only background catalog prewarm. Existing Stage 01, fresh isolated muted profile, native mouse/touch menu and resume button, press/motion/release and learning choice/return buttons, normal live process frames and real naturally spawned actors; no actor injection, fixed positions, process disabling, simulation stepping, terrain changes or fabricated clears. GPU frames and sampled source-foot geometry need separate visual review; no new battlefield art, all40 UI, startup timing, full battle or remastered terrain signoff. Concurrent source changes invalidate final-source signoff even if inputs pass."}
	var file: FileAccess = FileAccess.open("user://qa_ui_pilot_gpu.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	else:
		check(false,"GPU report opens in isolated user profile")
	print("UI_PILOT_GPU ",JSON.stringify({"checks":checks,"failures":failures.size(),"report":ProjectSettings.globalize_path("user://qa_ui_pilot_gpu.json"),"captures":captures.size(),"simulationElapsed":app.game.elapsed,"movingEnemies":moving}))
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if not guarded_profile(): quit(2);return
	initial_source_hashes = source_hashes()
	print("UI_PILOT_GPU_SOURCES ",JSON.stringify(initial_source_hashes))
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://ui-pilot-gpu-fresh.json"
	for setting in ["music","voice","effects"]: fixture.data.settings[setting] = false
	if not check(fixture.write_save(),"Fresh muted isolated GPU profile saves"): quit(2);return
	app = PilotMain.new()
	app.progress = fixture
	root.add_child(app)
	await settle()
	app._select_map(0)
	app._begin_battle()
	app.game.game_event.connect(func(event: Dictionary):
		if str(event.get("type","")) == "recruitment_queued": orders.append(event.duplicate(true))
	)
	await settle()
	started_usec = Time.get_ticks_usec()
	await verify_menu("mouse")
	await verify_menu("touch")
	await capture("1280x800-current-hud")
	if await begin_drag("archer"):
		await hover_and_capture("archer",Vector2i(1280,800))
		var destination: Vector2 = await hover_and_capture("archer",Vector2i(1440,900))
		await drop("archer",destination)
	await capture("1440x900-production-hud")
	if await begin_drag("spear"):
		await hover_and_capture("spear",Vector2i(1440,900))
		var destination: Vector2 = await hover_and_capture("spear",Vector2i(1280,800))
		await drop("spear",destination)
	await capture("1280x800-production-hud")
	await click(app.speed_button)
	check(app.game.speed == 2.0,"Actual GPU speed button enables the existing2x simulation setting")
	var live_start: int = Time.get_ticks_usec()
	var next_sample: float = 0.0
	var captured_thresholds: Dictionary = {}
	var logged: int = -1
	while float(Time.get_ticks_usec()-live_start)/1000000.0 < 45.0 and not app.game.finished:
		await process_frame
		await answer_learning()
		var wall_seconds: float = float(Time.get_ticks_usec()-live_start)/1000000.0
		if wall_seconds >= next_sample:
			sample_natural_motion()
			next_sample = wall_seconds + 2.0
		if int(wall_seconds)/10 > logged:
			logged = int(wall_seconds)/10
			print("UI_PILOT_GPU_PROGRESS wall=",snappedf(wall_seconds,.1)," simulation=",snappedf(app.game.elapsed,.1)," wave=",app.game.wave," enemies=",app.game.enemies.size()," learning=",app.learning_transition.phase)
		for threshold in [12,26,39]:
			if wall_seconds < threshold or captured_thresholds.has(threshold) or not app.quiz_task.is_empty(): continue
			captured_thresholds[threshold] = true
			await resize(Vector2i(1440,900) if threshold == 26 else Vector2i(1280,800))
			await capture(str(root.size.x) + "x" + str(root.size.y) + "-natural-" + str(threshold) + "s")
	await capture("final-natural-frame")
	await finish()
