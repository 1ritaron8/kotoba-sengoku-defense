extends SceneTree
## Final visual/input regression. Only actual initial supply and the Main toolbar.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []
var images: Array[String] = []
var observations: Array = []
var events: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok: failures.append(note); push_error(note)

func settle() -> void:
	app._process(0.0)
	app.game._emit_state()
	app.troops_3d.sync_actor_states(app.game.actor_states())
	app.game.queue_redraw()
	app.game.actor_overlay.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func save_image(name_value: String) -> Image:
	await settle()
	var image: Image = root.get_texture().get_image()
	var path: String = qa_project_path("dist/preview-premium-placement-") + name_value + ".png"
	check(image.save_png(path) == OK, "Actual GPU image saves: " + name_value)
	images.append(path)
	return image

func mouse_motion(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame

func mouse_click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	# The native OS pointer is deliberately not moved to these coordinates.
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = button
	press.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func deploy_count() -> int:
	var count: int = 0
	for event in events:
		if str(event.get("action", event.get("type", ""))) == "deploy": count += 1
	return count

func hints_for(type_name: String) -> Array:
	var result: Array = []
	for hint in app.game.placement_hints:
		if hint.x < 0: continue
		var preview: Dictionary = app.game.placement_preview(hint)
		check(bool(preview.valid), "Advertised " + type_name + " hint is accepted by the actual commit query")
		if bool(preview.valid):
			var norm: Vector2 = Vector2(float(preview.position.x), float(preview.position.y))
			result.append({"point": norm, "screen": app.game.field_rect.position + norm * app.game.field_rect.size})
	check(not result.is_empty(), "Actual " + type_name + " has at least one legal indicated post")
	return result

func marker_pixels(before: Image, after: Image, hints: Array, type_name: String) -> void:
	for hint in hints:
		var center: Vector2i = Vector2i(hint.screen)
		var changed: int = 0
		var bright_role_pixels: int = 0
		for y in range(center.y-12, center.y+13):
			for x in range(center.x-12, center.x+13):
				if x < 0 or y < 0 or x >= after.get_width() or y >= after.get_height(): continue
				var a: Color = before.get_pixel(x,y)
				var b: Color = after.get_pixel(x,y)
				if absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b) > .075: changed += 1
				if type_name == "spear" and b.g > .60 and b.b > .45 and b.g-b.r > .12: bright_role_pixels += 1
				# The actual field colour grade reduces gold to about .737 red.
				# Test its visible warm chroma, rather than ungraded shader RGB.
				elif type_name == "archer" and b.r > .60 and b.g > .48 and b.r-b.b > .16: bright_role_pixels += 1
		check(changed >= 80, "Bright post marker changes at least 80 actual pixels: " + type_name + " " + str(hint.point))
		check(bright_role_pixels >= 12, "Role-coloured cross remains visible over photograph: " + type_name + " " + str(hint.point))
		observations.append({"size": {"x":root.size.x,"y":root.size.y}, "type":type_name,"position":{"x":hint.point.x,"y":hint.point.y},"changedPixels":changed,"rolePixels":bright_role_pixels})

func invalid_point() -> Vector2:
	for y in [.10,.25,.45,.65]:
		for x in [.15,.35,.55,.75,.90]:
			var point: Vector2 = Vector2(x,y)
			if not bool(app.game.placement_preview(point).valid): return point
	return Vector2(.98,.05)

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/premium-placement/").to_lower()) or DisplayServer.get_name() == "headless":
		push_error("This final visual/input fixture requires the isolated premium-placement GPU profile")
		quit(2); return
	var store: RefCounted = Store.new()
	store.save_path = "user://premium-placement-%d.json" % Time.get_ticks_msec()
	store.data.settings = {"music":false,"voice":false,"effects":false}
	check(store.write_save(), "Fresh starter-only profile saves without fabricated clears")
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = store.save_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.atmosphere.set_process(false)
	app.combat_feedback.set_process(false)
	app.selected_portrait.set_process(false)
	app.player.stop()
	app.player.stream = null
	app.game.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	for view in [Vector2i(1280,800), Vector2i(1920,1080)]:
		root.size = view
		root.content_scale_size = view
		await process_frame
		app._select_tier(0)
		app._select_map(0)
		app._begin_battle()
		app.game.set_process(false)
		await create_timer(.75).timeout
		app.learning_field.clear()
		await settle()
		check(Vector2(root.content_scale_size) == app.get_viewport().get_visible_rect().size, "Pixel and logical UI coordinates match this native test viewport")
		check(app.game.gold == 280 and app.game.units.is_empty(), "New actual battle uses unchanged original 280 supply: " + str(view))
		check(app.progress.data.maps.is_empty(), "Visual fixture fabricates no campaign clears")
		check(app.game.input_enabled and app.modal == null and not app.front_end.visible, "Actual battlefield input is available")
		var opening: Image = root.get_texture().get_image()
		var initial_deploys: int = deploy_count()
		for type_name in ["archer","spear"]:
			var gold_before: int = app.game.gold
			var units_before: int = app.game.units.size()
			var deploys_before: int = deploy_count()
			var card: Button = app.army_grid.find_child("DeployCard_" + type_name, true, false)
			check(card != null and not card.disabled and card.is_visible_in_tree(), "Actual toolbar contains enabled starter card: " + type_name)
			if card == null: continue
			card.pressed.emit()
			check(app.game.pending.get("type","") == type_name and bool(app.game.pending.get("preview",false)), "Actual card begins correct free preview: " + type_name)
			check(app.game.gold == gold_before and int(app.game.pending.get("paid",-1)) == 0 and deploy_count() == deploys_before, "Choosing reserves no supply or successful deployment event")
			var hints: Array = hints_for(type_name)
			if hints.is_empty(): continue
			await mouse_motion(hints[0].screen)
			check(bool(app.game.placement_preview(hints[0].point).visible), "Native mouse motion exposes preview at indicated legal post")
			var preview_image: Image = await save_image("%dx%d-%s-valid" % [view.x,view.y,type_name])
			marker_pixels(opening, preview_image, hints, type_name)
			var invalid_norm: Vector2 = invalid_point()
			var invalid_screen: Vector2 = app.game.field_rect.position + invalid_norm * app.game.field_rect.size
			await mouse_motion(invalid_screen)
			var invalid_query: Dictionary = app.game.placement_preview(invalid_norm)
			check(not bool(invalid_query.valid) and not str(invalid_query.reason).is_empty(), "Invalid terrain returns an explicit current placement reason")
			await settle()
			check(app.hint_line.is_visible_in_tree() and app.hint_line.text.contains(str(invalid_query.reason)), "Actual lower hint displays the current invalid terrain reason alongside the world red X")
			await mouse_click(invalid_screen)
			check(app.game.gold == gold_before and app.game.units.size() == units_before and deploy_count() == deploys_before, "Invalid native click changes neither money, army nor success event")
			check(not app.game.pending.is_empty(), "Invalid native click preserves chosen preview")
			if view.x == 1280: await save_image("1280x800-" + type_name + "-invalid")
			await mouse_motion(hints[0].screen)
			await mouse_click(hints[0].screen)
			check(app.game.units.size() == units_before + 1 and app.game.pending.is_empty(), "Actual click-event position commits one " + type_name)
			var cost: int = int(app.progress.unit_definition(type_name).cost)
			check(app.game.gold == gold_before-cost and deploy_count() == deploys_before+1, "Successful native placement deducts exact catalog cost and emits one deploy")
			if app.game.units.size() == units_before + 1:
				check(app.game.units[-1].position.distance_to(hints[0].point) < .00001, "Committed world anchor matches visible preview, including ground rail projection")
			await mouse_click(hints[0].screen)
			check(app.game.units.size() == units_before+1 and app.game.gold == gold_before-cost and deploy_count() == deploys_before+1, "Repeated click selects existing soldier without double charge")
			await settle()
			check(not app.army_panel.get_global_rect().has_point(hints[0].screen), "Selected information inspector does not cover the placed actor")
			await save_image("%dx%d-%s-placed" % [view.x,view.y,type_name])
			opening = root.get_texture().get_image()
		check(app.game.gold == 155 and app.game.units.size() == 2 and deploy_count() == initial_deploys+2, "Two actual paid starter placements use exactly 125 supply")
		var cancel_card: Button = app.army_grid.find_child("DeployCard_archer", true, false)
		cancel_card.pressed.emit()
		if not app.game.units.is_empty():
			var occupied: Vector2 = app.game.units[0].position
			await mouse_motion(app.game.field_rect.position + occupied*app.game.field_rect.size)
			await settle()
			var occupied_preview: Dictionary = app.game.placement_preview(occupied)
			check(not bool(occupied_preview.valid) and str(occupied_preview.reason).contains("다른 병력"), "Occupied post has a specific overlap reason")
			check(app.hint_line.is_visible_in_tree() and app.hint_line.text.contains(str(occupied_preview.reason)), "Lower hint displays occupied-post reason without a failed deployment event")
		await mouse_motion(app.game.field_rect.position + Vector2(.9,.3)*app.game.field_rect.size)
		await mouse_click(app.game.field_rect.position + Vector2(.9,.3)*app.game.field_rect.size, MOUSE_BUTTON_RIGHT)
		check(app.game.pending.is_empty() and app.game.gold == 155 and app.game.units.size() == 2, "Right-click cancellation costs no supply")
	var report: Dictionary = {"checks":checks,"failures":failures,"images":images,"observations":observations,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Actual Main starter cards and native event-position input at 1280x800/1920x1080; initial budget, valid preview/invalid/cancel/exactly-once commit, all indicated post pixel visibility. Gameplay clocks frozen only for repeatable image comparison; no fabricated clears, units, reward or money."}
	var output: FileAccess = FileAccess.open("user://qa_premium_placement_capture.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")); output.close()
	print("PREMIUM_PLACEMENT_GPU ", JSON.stringify({"checks":checks,"failures":failures,"images":images,"gpu":RenderingServer.get_video_adapter_name()}))
	app.battle_audio.shutdown()
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
