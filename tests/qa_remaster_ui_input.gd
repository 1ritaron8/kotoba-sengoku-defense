extends SceneTree
## Native input regression for the common battlefield UI, in disposable profiles.
## Frozen simulation fixtures exercise UI transactions; they do not prove GPU art
## quality, OS focus delivery, campaign completion, or naturally evolving waves.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> bool:
	checks += 1
	if not value:
		failures.append(note)
		push_error("REMASTER_INPUT " + note)
	return value

func canonical(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func guarded_profile() -> bool:
	var allowed: String = canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	var local: String = canonical(OS.get_environment("LOCALAPPDATA"))
	var save: String = canonical(ProjectSettings.globalize_path("user://"))
	return check(roaming.is_absolute_path() and roaming.begins_with(allowed + "/remaster-input-") and local == roaming and save.begins_with(roaming + "/"), "Verifier refuses all nonisolated player profiles")

func settle(count: int = 2) -> void:
	for unused in range(count): await process_frame

func send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await settle(1)

func mouse(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT, device: int = 0) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.device = device
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	await send(event)

func motion(point: Vector2, held: bool = true, device: int = 0) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.device = device
	await send(event)

func key(code: Key, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	await send(event)
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	await send(event)

func touch(point: Vector2, pressed: bool, index: int = 0) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	await send(event)

func touch_motion(point: Vector2, index: int = 0) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.position = point
	event.index = index
	await send(event)

func transactional_state() -> Dictionary:
	var game: Node = app.game
	return {"gold":game.gold,"jobs":game.recruitment_queue.duplicate(true),"actors":game.units.duplicate(true),"nextActor":game.next_id,"nextJob":game.next_recruitment_id,"nextEvent":game.next_event_id,"recruits":game.recruits,"selection":game.selected_id,"pending":game.pending.duplicate(true),"chosen":app.chosen_unit_id,"progress":app.progress.data.duplicate(true),"save":FileAccess.get_file_as_bytes(app.progress.save_path)}

func clear_gesture() -> bool:
	return app.deployment_drag.is_empty() and str(app.deployment_press_unit_id).is_empty() and not app.deployment_release_pending and not app.game.ui_deployment_active and app.troops_3d.ui_deployment_preview.is_empty()

func card(id: String) -> Button:
	return app.army_grid.get_node_or_null("DeployCard_" + id) as Button

func center(id: String) -> Vector2:
	var control: Button = card(id)
	return control.get_global_rect().get_center() if control != null else Vector2(-1,-1)

func normalized(point) -> Vector2:
	return point if point is Vector2 else Vector2(float(point.get("x", -1)), float(point.get("y", -1)))

func legal_screen(id: String) -> Vector2:
	if str(app.game.placement_contract(id).get("deploymentKind", "placed")) == "marching":
		var base: Dictionary = app.game.ground_combat.select_march_base()
		if not base.is_empty():
			var screen: Vector2 = app.game.field_point_to_screen(normalized(base.position))
			if not app._deployment_surface_point(screen).is_empty(): return screen
	else:
		for zone in app.game.zones:
			var point: Vector2 = app.game._zone_placement_hint(zone,id)
			if point.x < 0 or not bool(app.game.deployment_preview(id,point).get("valid", false)): continue
			var screen: Vector2 = app.game.field_point_to_screen(point)
			if not app._deployment_surface_point(screen).is_empty(): return screen
	return Vector2(-1,-1)

func begin(id: String) -> Dictionary:
	var before: Dictionary = transactional_state()
	var start: Vector2 = center(id)
	await motion(start,false)
	await mouse(start,true)
	check(transactional_state() == before, id + " native press leaves saved selection, pending preview, money, jobs and IDs unchanged")
	await motion(start + Vector2(12,-30))
	check(not app.deployment_drag.is_empty() and str(app.deployment_drag.get("unitId", "")) == id, id + " native held motion starts exactly one drag")
	check(transactional_state() == before, id + " native drag before commitment has no transactional side effects")
	return before

func make_app(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	var fixture: RefCounted = Store.new()
	fixture.save_path = "user://remaster-input-" + str(dimensions.x) + ".json"
	fixture.data.settings.music = false
	fixture.data.settings.voice = false
	fixture.data.settings.effects = false
	check(fixture.write_save(), "Disposable fresh profile can be saved")
	app = load("res://native/main.tscn").instantiate()
	app.progress = fixture
	root.add_child(app)
	app.set_process(false)
	app.game.set_process(false)
	app.atmosphere.set_process(false)
	app.troops_3d.set_process(false)
	await settle(3)
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	await settle(3)
	app._layout()
	check(app._can_prepare_placement(), "Existing Stage 01 is ready for native deployment input at " + str(dimensions))
	check(card("archer") != null and card("spear") != null and not card("archer").disabled and not card("spear").disabled, "Fresh profile exposes both real starter roster cards")

func cleanup() -> void:
	if not is_instance_valid(app): return
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await settle(3)
	app = null

func verify_size(dimensions: Vector2i) -> void:
	await make_app(dimensions)
	if not app._can_prepare_placement():
		await cleanup()
		return
	var bow: Vector2 = legal_screen("archer")
	var base: Vector2 = legal_screen("spear")
	check(bow.x >= 0 and base.x >= 0, "Both actual ranged position and friendly origin are unobstructed in " + str(dimensions))
	if bow.x < 0 or base.x < 0:
		await cleanup()
		return
	for control in [app.hud_gold,app.hud_health,app.hud_wave,app.hud_capacity,app.pause_button,app.speed_button,app.battle_menu_button,app.army_toolbar]:
		check(root.get_visible_rect().encloses(control.get_global_rect()), "Actual HUD/roster remains inside viewport: " + str(control.name) + " " + str(dimensions))
	# Preserve the existing deliberate click/R contract alongside drag and drop:
	# a marching click dispatches; a stationary click prepares a free preview.
	var before: Dictionary = transactional_state()
	await mouse(center("spear"),true)
	check(transactional_state() == before, "Short click press still does not select or spend")
	await mouse(center("spear"),false)
	check(app.chosen_unit_id == "spear" and app.game.pending.is_empty() and app.game.recruitment_queue.size() == before.jobs.size()+1 and app.game.gold == int(before.gold)-app.game.recruit_cost("spear") and app.game.units.is_empty(), "Deliberate marching-card release retains one paid delayed dispatch")
	before = transactional_state()
	await mouse(center("archer"),true)
	check(transactional_state() == before, "Stationary click press preserves selection, saved progress and the accepted marching order")
	await mouse(center("archer"),false)
	check(app.chosen_unit_id == "archer" and not app.game.pending.is_empty() and str(app.game.pending.get("type","")) == "archer" and app.game.gold == int(before.gold) and app.game.recruitment_queue == before.jobs and app.game.units.is_empty(), "Deliberate stationary-card release retains the existing unpaid placement preview without charging")
	await key(KEY_R)
	check(app.game.pending.is_empty() and app.game.gold == int(before.gold) and app.game.recruitment_queue == before.jobs, "R cancels the deliberately prepared stationary preview without changing paid orders")
	before = await begin("archer")
	await motion(bow)
	check(bool(app.deployment_drag.get("preview",{}).get("valid",false)) and transactional_state() == before, "Legal hover is valid and pure")
	await key(KEY_R)
	await key(KEY_R,true)
	check(transactional_state() == before and not app.deployment_drag.is_empty(), "R and key echo during drag cannot charge or dispatch")
	await mouse(bow,false)
	check(clear_gesture() and app.game.recruitment_queue.size() == before.jobs.size()+1 and app.game.gold == int(before.gold)-app.game.recruit_cost("archer") and app.game.units.is_empty(), "Valid native stationary drop adds exactly one paid delayed order to the retained click dispatch")
	var committed: Dictionary = transactional_state()
	await mouse(bow,false)
	card("archer").pressed.emit()
	check(transactional_state() == committed, "Duplicate release and delayed card signal cannot replay completed drag")
	# All cancellation paths preserve the previously accepted paid archer order.
	for cause in ["reserved","HUD","offfield","escape","right","focus","modal","learning"]:
		before = await begin("archer" if cause == "reserved" else "spear")
		await motion(bow if cause == "reserved" else base)
		match cause:
			"reserved":
				check(not bool(app.deployment_drag.get("preview",{}).get("valid",false)), "Reserved ranged destination cannot produce another order")
				await mouse(bow,false)
			"HUD": await mouse(app.hud_gold.get_global_rect().get_center(),false)
			"offfield": await mouse(Vector2(-20,-20),false)
			"escape": await key(KEY_ESCAPE)
			"right": await mouse(base,true,MOUSE_BUTTON_RIGHT)
			"focus": app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"modal": app._show_pause_menu()
			"learning":
				app.game.set_input_enabled(false)
				app.context_task_active = true
				app._process(0.0)
		await settle()
		check(app.deployment_drag.is_empty() and app.troops_3d.ui_deployment_preview.is_empty() and transactional_state() == before, cause + " clears preview and leaves the prior paid order, balance, IDs and save intact")
		await mouse(base,false)
		if cause == "right": await mouse(base,false,MOUSE_BUTTON_RIGHT)
		if cause == "focus": app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		if cause == "modal": app._close_modal(true)
		if cause == "learning":
			app.context_task_active = false
			app.game.set_input_enabled(true)
		check(clear_gesture(), cause + " leaves no canceled gesture ownership after release")
	# Focus loss can omit release entirely. Regaining focus must allow R again.
	before = await begin("spear")
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(clear_gesture() and transactional_state() == before, "Lost release on focus change clears all transient ownership immediately")
	await key(KEY_R)
	check(not app.game.pending.is_empty() and str(app.game.pending.get("type","")) == "archer" and app.game.recruitment_queue.size() == before.jobs.size() and app.game.gold == int(before.gold), "Separate stationary R works after focus recovery and opens the existing unpaid preview")
	await key(KEY_ESCAPE)
	# Pause freezes time but the established recruitment rule permits submission.
	app.game.paused = true
	app.game._emit_state()
	before = await begin("spear")
	await motion(base)
	await mouse(base,false)
	check(clear_gesture() and app.game.paused and app.game.recruitment_queue.size() == before.jobs.size()+1 and app.game.gold == int(before.gold)-app.game.recruit_cost("spear"), "Paused battle accepts one delayed order without unpausing simulation")
	app.game.paused = false
	app.game._emit_state()
	# Replenished fixture funds allow touch and radius tests; no campaign claim.
	app.game.gold = 1000
	app.game._emit_state()
	before = transactional_state()
	await touch(center("spear"),true,3)
	await mouse(center("spear"),true,MOUSE_BUTTON_LEFT,-1)
	await touch_motion(base,3)
	check(not app.deployment_drag.is_empty() and transactional_state() == before, "Touch plus emulated mouse remains one pure gesture")
	await touch(base,false,4)
	check(not app.deployment_drag.is_empty() and transactional_state() == before, "Foreign touch release cannot submit owning finger's order")
	await touch(base,false,3)
	check(clear_gesture() and app.game.recruitment_queue.size() == before.jobs.size()+1 and app.game.gold == int(before.gold)-app.game.recruit_cost("spear"), "Matching touch release submits once")
	committed = transactional_state()
	await mouse(base,false,MOUSE_BUTTON_LEFT,-1)
	await touch(base,false,3)
	check(transactional_state() == committed, "Emulated mouse and duplicate touch releases cannot submit again")
	var base_norm: Vector2 = app.game.screen_to_field_point(base)
	var actual: Dictionary = app.game.deployment_preview("spear",base_norm)
	var radius: float = float(actual.get("dropRadius",0))
	check(radius > 0 and bool(actual.get("valid",false)), "Marching preview reports the authored friendly origin and current drop radius")
	var outside: Vector2 = base_norm + Vector2(radius+0.012,0)
	var outside_screen: Vector2 = app.game.field_point_to_screen(outside)
	before = await begin("spear")
	await motion(outside_screen)
	check(not bool(app.deployment_drag.get("preview",{}).get("valid",false)), "Marching drag outside current backend radius is rejected")
	await mouse(outside_screen,false)
	check(clear_gesture() and transactional_state() == before, "Out-of-radius marching release does not become stationary placement")
	before = transactional_state()
	await mouse(center("gunner"),true)
	await motion(base)
	await mouse(base,false)
	check(clear_gesture() and transactional_state() == before, "Locked card's pointer gesture cannot select, charge, dispatch or leak release")
	observations.append({"size":[dimensions.x,dimensions.y],"initialProfile":"fresh two-starter fixture","marchRadius":radius,"stationaryScreen":[bow.x,bow.y],"marchScreen":[base.x,base.y],"queuedOrders":app.game.recruitment_queue.size(),"scope":"actual Godot native mouse/touch/key input and simulated focus notifications; frozen simulation"})
	await cleanup()

func run() -> void:
	if not guarded_profile(): quit(2); return
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
		await verify_size(dimensions)
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"profile":ProjectSettings.globalize_path("user://"),"driver":DisplayServer.get_name(),"clickContract":"Retained deliberate stationary click opens an unpaid preview; marching click dispatches once; R retains its existing action.","scope":"Native Godot input in existing Stage 01 UI with frozen combat, real recruitment rules and disposable saves. No GPU art/natural-wave/OS-focus-delivery claim."}
	var output: FileAccess = FileAccess.open("user://qa-remaster-ui-input.json",FileAccess.WRITE)
	if output == null: quit(2); return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("REMASTER_INPUT ",checks," checks / ",failures.size()," failures; report=",ProjectSettings.globalize_path("user://qa-remaster-ui-input.json"))
	quit(0 if failures.is_empty() else 1)
