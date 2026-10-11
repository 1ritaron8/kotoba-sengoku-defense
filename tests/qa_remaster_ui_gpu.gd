extends SceneTree
## Disposable GPU evidence of real Main UI, native commands and normal timers.
## Never fabricates enemies, friendly actors, budget, levels or campaign clears.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var images: Array[String] = []
var observations: Array = []
var events: Array = []
var mouse_held: bool = false
var pointer: Vector2 = Vector2.ZERO
var resolution: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> bool:
	checks += 1
	if not value:
		failures.append(note)
		push_error("REMASTER_UI_GPU " + note)
	return value

func canonical(value: String) -> String:
	return value.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func guarded_profile() -> bool:
	var allowed: String = canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	var local: String = canonical(OS.get_environment("LOCALAPPDATA"))
	var user_path: String = canonical(ProjectSettings.globalize_path("user://"))
	return check(DisplayServer.get_name() != "headless" and roaming.begins_with(allowed + "/remaster-ui-gpu/") and roaming == local and user_path.begins_with(roaming + "/"), "Only an isolated remaster-ui-gpu GPU profile can run this verifier")

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func capture(suffix: String) -> void:
	await settle()
	var framebuffer: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("user://" + resolution + "-" + suffix + ".png")
	check(framebuffer.get_width() == root.size.x and framebuffer.get_height() == root.size.y, "GPU framebuffer matches native " + resolution + " dimensions")
	check(framebuffer.save_png(path) == OK, "GPU image saves: " + resolution + "-" + suffix)
	images.append(path)
	print("REMASTER_UI_GPU_CAPTURE ", path)

func mouse_motion(point_value: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point_value
	event.global_position = point_value
	event.relative = point_value - pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_held else 0
	pointer = point_value
	Input.parse_input_event(event)
	await process_frame

func mouse_button(point_value: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point_value
	event.global_position = point_value
	event.button_index = button
	event.pressed = pressed
	if button == MOUSE_BUTTON_LEFT: mouse_held = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_held else 0
	pointer = point_value
	Input.parse_input_event(event)
	await process_frame

func click(point_value: Vector2) -> void:
	await mouse_motion(point_value)
	await mouse_button(point_value, true)
	await mouse_button(point_value, false)
	await settle()

func key(code: int) -> void:
	for held in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = held
		Input.parse_input_event(event)
		await process_frame

func point(value) -> Vector2:
	return value if value is Vector2 else Vector2(float(value.get("x", -1)), float(value.get("y", -1)))

func screen(norm: Vector2) -> Vector2:
	return app.game.get_global_transform_with_canvas() * app.game._screen(norm)

func legal(id: String) -> Vector2:
	if str(app.game.placement_contract(id).deploymentKind) == "marching":
		var base: Dictionary = app.game.ground_combat.select_march_base()
		return point(base.position) if not base.is_empty() else Vector2(-1, -1)
	for zone in app.game.zones:
		var hint: Vector2 = app.game._zone_placement_hint(zone, id)
		if hint.x >= 0 and bool(app.game.deployment_preview(id, hint).get("valid", false)): return hint
	return Vector2(-1, -1)

func invalid(id: String) -> Vector2:
	for y in [.13, .35, .55, .78]:
		for x in [.08, .20, .45, .66, .87]:
			var candidate: Vector2 = Vector2(x, y)
			if not bool(app.game.deployment_preview(id, candidate).get("valid", false)) and not app._deployment_surface_point(screen(candidate)).is_empty(): return candidate
	return Vector2(.08, .13)

func count_event(action: String) -> int:
	var count: int = 0
	for event in events:
		if str(event.get("action", "")) == action: count += 1
	return count

func json_rect(rect: Rect2) -> Dictionary:
	return {"x":rect.position.x, "y":rect.position.y, "width":rect.size.x, "height":rect.size.y}

func ruby_geometry(control: Control, note: String) -> void:
	if not control.is_visible_in_tree() or control.word.is_empty(): return
	var layout: Dictionary = control.get_text_layout()
	var visible_readings: int = 0
	var widget: Rect2 = Rect2(Vector2.ZERO, control.size)
	for run in layout.runs:
		check(widget.grow(.2).encloses(run.bounds), resolution + ": " + note + " fits every Japanese/Korean text run inside its real widget")
		if str(run.role) == "reading":
			visible_readings += 1
			check(int(run.size) >= control.min_reading_size, resolution + ": " + note + " preserves actual furigana point size")
	check(visible_readings > 0, resolution + ": " + note + " includes authored hiragana readings")
	observations.append({"resolution":resolution, "ruby":note, "jp":str(control.word.get("jp", "")), "reading":str(control.word.get("reading", "")), "rect":json_rect(control.get_global_rect()), "runs":layout.runs.size(), "readingRuns":visible_readings})

func viewport_geometry() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size))
	check(bounds.encloses(app.hud_bar.get_global_rect()), resolution + ": HUD fits native viewport")
	check(bounds.encloses(app.army_toolbar.get_global_rect()), resolution + ": roster dock fits native viewport")
	check(not app.recruit_button.is_visible_in_tree(), resolution + ": redundant deployment button stays hidden")
	var unlocked: int = 0
	var locked: int = 0
	for card in app.army_grid.get_children():
		if not card is Button: continue
		check(card.is_visible_in_tree() and bounds.encloses(card.get_global_rect()), resolution + ": real card is visible and unclipped: " + str(card.name))
		if card.disabled: locked += 1
		else: unlocked += 1
	check(unlocked == 2 and locked == 6, resolution + ": starter-only roster shows two available and six locked cards")
	check(app.hud_gold.text.contains(str(app.game.gold)), resolution + ": supply label reflects current authoritative budget")
	ruby_geometry(app.active_word, "active vocabulary")
	ruby_geometry(app.example_label, "example sentence")
	var snapshot: Dictionary = app.game.snapshot()
	observations.append({"resolution":resolution, "field":json_rect(app.field_clip.get_global_rect()), "hud":json_rect(app.hud_bar.get_global_rect()), "roster":json_rect(app.army_toolbar.get_global_rect()), "queue":json_rect(app.production_panel.get_global_rect()), "learning":json_rect(app.learning_panel.get_global_rect()), "budget":snapshot.gold, "activeActors":snapshot.units.size(), "actorCap":snapshot.unitLimit, "orders":snapshot.recruitmentQueue.size(), "orderCap":snapshot.recruitmentCapacity})

func world_geometry() -> void:
	if app.learning_readout_expanded: return
	var landmarks: Array = []
	for objective in app.game.objectives:
		landmarks.append({"kind":"objective", "position":objective.position})
	for route in app.game.paths:
		if not route.points.is_empty():
			landmarks.append({"kind":"enemy entrance", "position":route.points[0]})
	for landmark in landmarks:
		var anchor: Vector2 = screen(point(landmark.position))
		check(app.field_clip.get_global_rect().has_point(anchor), resolution + ": " + str(landmark.kind) + " is inside the native camera field")
		for panel in [app.hud_bar, app.army_toolbar, app.learning_panel, app.production_panel, app.army_panel, app.camera_controls]:
			if panel.is_visible_in_tree():
				check(not panel.get_global_rect().has_point(anchor), resolution + ": " + str(landmark.kind) + " remains clear of " + str(panel.name))
		observations.append({"resolution":resolution, "landmark":str(landmark.kind), "screen":{"x":anchor.x,"y":anchor.y}})

func drag(id: String, destination: Vector2, hold_capture: String = "") -> void:
	var card: Button = app.army_grid.find_child("DeployCard_" + id, true, false)
	if not check(card != null and card.is_visible_in_tree() and not card.disabled, resolution + ": actual drag source exists: " + id): return
	var budget: int = app.game.gold
	var jobs: int = app.game.recruitment_queue.size()
	var submitted: int = count_event("recruitment_queued")
	var card_center: Vector2 = card.get_global_rect().get_center()
	await mouse_motion(card_center)
	await mouse_button(card_center, true)
	await mouse_motion(screen(destination))
	await settle()
	check(not app.deployment_drag.is_empty() and str(app.deployment_drag.get("unitId", "")) == id, resolution + ": native held movement enters the correct UI drag")
	var preview: Dictionary = app.deployment_drag.get("preview", {})
	check(bool(preview.get("valid", false)) and bool(preview.get("visible", false)), resolution + ": legal held drag exposes valid live world preview")
	check(app.game.gold == budget and app.game.recruitment_queue.size() == jobs and count_event("recruitment_queued") == submitted, resolution + ": held drag creates no paid order")
	if not hold_capture.is_empty(): await capture(hold_capture)
	await mouse_button(screen(destination), false)
	await settle()
	var cost: int = app.game.recruit_cost(id)
	check(app.deployment_drag.is_empty() and not app.game.ui_deployment_active, resolution + ": matching release clears transient drag ownership")
	check(app.game.gold == budget - cost and app.game.recruitment_queue.size() == jobs + 1 and count_event("recruitment_queued") == submitted + 1, resolution + ": one real drop accepts exactly one paid order")
	check(app.production_panel.is_visible_in_tree(), resolution + ": accepted actual order appears in production queue")

func capture_resolution(view: Vector2i) -> void:
	root.size = view
	root.content_scale_size = view
	resolution = "%dx%d" % [view.x, view.y]
	await settle()
	app._show_home()
	await capture("home")
	app._select_tier(0)
	app._select_map(0)
	await create_timer(.75).timeout
	await capture("briefing")
	app._begin_battle()
	await create_timer(1.0).timeout
	check(app.battle_started and not app.battle_finished and app.game.running and not app.front_end.visible, resolution + ": actual starter Stage 01 begins normally")
	check(app.progress.data.maps.is_empty(), resolution + ": GPU fixture fabricates no campaign clears")
	if not bool(app.game.paused): await click(app.pause_button.get_global_rect().get_center())
	check(bool(app.game.paused), resolution + ": actual pause button freezes simulation for repeatable UI evidence")
	viewport_geometry()
	world_geometry()
	await capture("opening")
	var readout_toggle: Button = app.army_toolbar.get_node_or_null("LearningReadoutToggle")
	if readout_toggle != null:
		await click(readout_toggle.get_global_rect().get_center())
		await settle()
		check(app.learning_readout_expanded and app.example_label.is_visible_in_tree(), resolution + ": actual learning toggle expands authored Japanese sentence and grammar")
		viewport_geometry()
		await capture("expanded-learning-readout")
		await click(readout_toggle.get_global_rect().get_center())
	var bow: Vector2 = legal("archer")
	var base: Vector2 = legal("spear")
	if check(bow.x >= 0 and base.x >= 0, resolution + ": starter map has legal ranged site and authored marching base"):
		await drag("archer", bow, "ranged-valid-drag")
		await capture("ranged-production")
		await drag("spear", base, "marching-valid-drag")
		await capture("parallel-production")
	var card: Button = app.army_grid.find_child("DeployCard_archer", true, false)
	var budget: int = app.game.gold
	var orders: int = app.game.recruitment_queue.size()
	await mouse_button(card.get_global_rect().get_center(), true)
	await mouse_motion(screen(invalid("archer")))
	await settle()
	check(not bool(app.deployment_drag.get("preview", {}).get("valid", false)), resolution + ": invalid held site displays a rejected preview")
	await capture("invalid-drag")
	await key(KEY_ESCAPE)
	await mouse_button(pointer, false)
	check(app.game.gold == budget and app.game.recruitment_queue.size() == orders, resolution + ": cancelling unsubmitted drag preserves accepted queue and supply")
	await click(app.pause_button.get_global_rect().get_center())
	check(not app.game.paused, resolution + ": actual pause button resumes unchanged timers and waves")
	var before: float = app.game.elapsed
	var deployed_before: int = count_event("deploy") + count_event("recruit")
	await create_timer(6.0).timeout
	check(app.game.elapsed > before + 4.0, resolution + ": unmodified real-time battle and concurrent production timers advance")
	check(count_event("deploy") + count_event("recruit") >= deployed_before + 2, resolution + ": actual accepted orders create actors after their normal production timers")
	check(app.game.enemies.size() > 0 and app.game.wave >= 1, resolution + ": enemies arise from the natural authored wave spawner")
	if not app.game.paused: await click(app.pause_button.get_global_rect().get_center())
	if not app.game.units.is_empty():
		var actor: Dictionary = app.game.units[0]
		await click(screen(actor.position))
		await settle()
		check(not app.game.snapshot().selected.is_empty(), resolution + ": native world click selects an actual produced actor")
		check(app.army_panel.is_visible_in_tree(), resolution + ": actual selection shows the information inspector")
		ruby_geometry(app.selected_word, "selected produced unit")
	viewport_geometry()
	world_geometry()
	await capture("natural-combat-selection")
	await click(app.battle_menu_button.get_global_rect().get_center())
	check(app.modal != null and app.modal_context == "pause", resolution + ": actual menu button opens the pause menu")
	await capture("pause-menu")
	var study: Button = find_button(app.modal_body, "학습 도감")
	if check(study != null, resolution + ": pause menu has an actual learning entry"):
		await click(study.get_global_rect().get_center())
		check(app.modal_context == "study", resolution + ": learning entry opens the real study screen")
		await capture("learning-entry")
	await key(KEY_ESCAPE)

func find_button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text.contains(text): return child
		var found: Button = find_button(child, text)
		if found != null: return found
	return null

func run() -> void:
	if not guarded_profile():
		quit(2)
		return
	var store: RefCounted = Store.new()
	store.save_path = "user://remaster-ui-gpu-starter.json"
	store.data.settings = {"music":false, "voice":false, "effects":false}
	check(store.write_save(), "Fresh isolated starter profile saves")
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = store.save_path
	root.add_child(app)
	app.game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var preparation_start: int = Time.get_ticks_msec()
	while not app.catalog_preparation_ready and app.catalog_preparation_error.is_empty() and Time.get_ticks_msec() - preparation_start < 240000:
		await process_frame
	check(app.catalog_preparation_ready and app.catalog_preparation_completed == 40, "Real startup prepares all forty catalog previews without bypassing the readiness gate")
	if not app.catalog_preparation_ready:
		failures.append("Catalog preparation did not complete: " + str(app.catalog_preparation_error))
	else:
		for view in [Vector2i(1440,900), Vector2i(1280,800)]:
			await capture_resolution(view)
	var report: Dictionary = {"checks":checks, "failures":failures, "images":images, "observations":observations, "gpu":RenderingServer.get_video_adapter_name(), "scope":"Actual Main GPU rendering at 1440x900 and 1280x800; starter Korean/Japanese/furigana, roster locks, native card drag, valid/invalid/cancel feedback, real paid concurrent recruitment, actual pause/menu/study navigation, and natural first-wave enemy spawns after real-time production. Uses public UI pauses only for repeatable captures; does not alter enemies, actors, budget, levels, unlocks, wave schedules or battle duration. This is early-wave visual evidence, not a full natural ten-minute battle completion."}
	var output: FileAccess = FileAccess.open("user://qa_remaster_ui_gpu.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("REMASTER_UI_GPU_RESULT ", JSON.stringify({"checks":checks, "failures":failures, "images":images, "gpu":report.gpu}))
	app.battle_audio.shutdown()
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
