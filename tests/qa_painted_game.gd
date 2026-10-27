extends SceneTree
## Actual Main and actual inputs; no battle funds, levels, HP or clocks injected.
## HQ owns the only rendered engine. Keep every capture if a later check fails.
const OUTPUT_ROOT: String = "res://tests/profiles/painted-game-fix-01"
const MAX_SECONDS: float = 240.0
const PERFORMANCE_SECONDS: float = 12.0
const FIRST_RUN_REPORT: String = "res://tests/profiles/painted-game-01/run-1791770940/report.json"
const INPUT_FAILURE_REPORT: String = "res://tests/profiles/painted-game-01/run-1791772255/report.json"
const SINGLE_FRAME_HOVER_REPORT: String = "res://tests/profiles/painted-game-01/run-1791773099/report.json"
const ROAD_EVIDENCE: String = "res://tests/profiles/painted-game-01/road-alignment.json"
const RoadOverlay = preload("res://tests/qa_painted_road_overlay.gd")
var app: Node
var started: int = 0
var stopped: bool = false
var observing: bool = false
var output_dir: String = ""
var check_rows: Array = []
var failures: Array[String] = []
var incomplete: Array[String] = []
var captures: Array = []
var events: Array = []
var input_trace: Array = []
var clicks: Dictionary = {}
var click_callbacks: Dictionary = {}
var sequence: int = 0
var ingress: Dictionary = {}
var paid_orders: Array = []
var frame_rows: Array = []
var evidence: Dictionary = {}
var phase: String = "setup"
var measurement_epoch: int = 0
var measuring: bool = false
var eligible_wall_seconds: float = 0.0
var source_hashes: Dictionary = {}
var hover_probes: Dictionary = {}
var destination_visits: Dictionary = {"briefing":0,"study":0,"context":0}
var previous_destination: String = "home"
var action_trace: Array = []
var action_keys: Dictionary = {}
var pointer_position: Vector2 = Vector2.ZERO
var pointer_left_down: bool = false
var observations: Array = []
var capture_buffers: Dictionary = {}

func destination_snapshot() -> Dictionary:
	if not is_instance_valid(app) or not is_instance_valid(app.get("game")): return {"appAlive":false}
	return {"appAlive":true,"clock":app.game.elapsed,"paused":app.game.paused,"running":app.game.running,"finished":app.game.finished,"betweenWaves":app.game.between_waves,"inputEnabled":app.game.input_enabled,"context":app.context_task_active,"modalContext":str(app.modal_context),"modalAlive":is_instance_valid(app.modal),"transition":str(app.learning_transition.phase) if is_instance_valid(app.learning_transition) else "missing","frontEndVisible":is_instance_valid(app.front_end) and app.front_end.visible,"frontEndView":str(app.front_end.view) if is_instance_valid(app.front_end) else "missing","barracksVisible":is_instance_valid(app.barracks) and app.barracks.visible,"trainingVisible":is_instance_valid(app.unit_training) and app.unit_training.visible}

func live_battle() -> bool:
	return alive() and app.battle_started and app.game.running and not app.game.paused and not app.game.finished and not app.game.between_waves and app.game.input_enabled and not app.context_task_active and not is_instance_valid(app.modal) and not app.front_end.visible and not app.unit_training.visible and not app.barracks.visible and not app._learning_screen_active()

func hash_sources() -> Dictionary:
	var result: Dictionary = {}
	for directory in ["res://native","res://assets/characters/painted-v1","res://assets/painted-battlefield"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.get_extension() in ["gd","json","png"]:
				var path: String = directory.path_join(filename)
				result[path] = FileAccess.get_sha256(path)
	for filename in ["qa_painted_game.gd","qa_painted_walk_review.gd","qa_painted_fix01_logic.gd"]:
		var path: String = "res://tests/"+filename
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	for path in ["res://project.godot","res://native/main.tscn","res://tests/qa_painted_road_overlay.gd","res://tests/qa_painted_fix01_rig.gd"]:
		if FileAccess.file_exists(path): result[path]=FileAccess.get_sha256(path)
	return result

func _initialize() -> void:
	call_deferred("run")

func bounded() -> bool:
	return not stopped and Time.get_ticks_usec()-started < int(MAX_SECONDS*1000000.0)

func alive() -> bool:
	return bounded() and is_instance_valid(app) and is_instance_valid(app.get("game"))

func check(ok: bool, note: String) -> bool:
	check_rows.append({"pass":ok,"note":note,"wallSeconds":wall_seconds()})
	if not ok:
		failures.append(note)
		push_error("PAINTED_GAME " + note)
	return ok

func wall_seconds() -> float:
	return float(Time.get_ticks_usec()-started)/1000000.0

func canonical(value: String) -> String:
	return value.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

func journal(kind: String, data: Dictionary = {}) -> void:
	if output_dir.is_empty(): return
	var path: String = output_dir.path_join("progress.jsonl")
	var file: FileAccess = FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify({"kind":kind,"wallSeconds":wall_seconds(),"phase":phase,"data":data}))
		file.close()

func settle(count: int = 3) -> void:
	for unused in range(count):
		if not bounded(): return
		await RenderingServer.frame_post_draw

func wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_usec()+int(seconds*1000000.0)
	while bounded() and Time.get_ticks_usec()<deadline:
		if bool(predicate.call()): return true
		await process_frame
	return bounded() and bool(predicate.call())

func visible_clip(control: Control) -> Rect2:
	var clip: Rect2 = control.get_viewport().get_visible_rect()
	var parent: Node = control.get_parent()
	while parent != null and parent != control.get_viewport():
		if parent is Control and parent.clip_contents:
			clip = clip.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return clip

func live_button(id: int) -> Button:
	var value: Variant = instance_from_id(id) if id>0 else null
	if not is_instance_valid(value) or not value is Button: return null
	if value.is_queued_for_deletion() or not value.is_inside_tree() or value.get_viewport()!=root: return null
	return value as Button

func property_button_id(name_value: String) -> int:
	if not is_instance_valid(app): return 0
	var value: Variant = app.get(name_value)
	return value.get_instance_id() if is_instance_valid(value) and value is Button else 0

func card_id(type_name: String) -> int:
	if not alive(): return 0
	var value: Node = app.army_grid.get_node_or_null("DeployCard_"+type_name)
	return value.get_instance_id() if value is Button else 0

func visible_button_text(parent: Node, fragment: String) -> int:
	if not is_instance_valid(parent): return 0
	for node in parent.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and not node.disabled and str(node.text).contains(fragment): return node.get_instance_id()
	return 0

func on_pressed(token: String, copied: Dictionary) -> void:
	if not clicks.has(token): return
	clicks[token].pressedSignals = int(clicks[token].pressedSignals)+1
	input_trace.append({"token":token,"stage":"pressed_signal","snapshot":copied.duplicate(true),"wallSeconds":wall_seconds()})

func on_gui(event: InputEvent, token: String, copied: Dictionary) -> void:
	if event is InputEventMouseButton:
		if clicks.has(token):
			var key: String = "guiPresses" if event.pressed else "guiReleases"
			clicks[token][key] = int(clicks[token].get(key,0))+1
		input_trace.append({"token":token,"stage":"gui_input","pressed":event.pressed,"button":event.button_index,"localPosition":str(event.position),"globalPosition":str(event.global_position),"snapshot":copied.duplicate(true),"wallSeconds":wall_seconds()})

func begin_observation(id: int, note: String) -> String:
	var button: Button = live_button(id)
	if not check(button != null and button.is_visible_in_tree() and not button.disabled,note+": a visible enabled button exists"):
		return ""
	sequence += 1
	var token: String = "%d:%d" % [sequence,id]
	var copied: Dictionary = {"instanceId":id,"path":str(button.get_path()),"text":button.text,"rect":str(button.get_global_rect()),"clip":str(visible_clip(button)),"disabled":button.disabled,"note":note}
	clicks[token] = {"snapshot":copied.duplicate(true),"pressedSignals":0,"dispatchCount":0,"guiPresses":0,"guiReleases":0,"pressIssued":0,"releaseIssued":0,"before":destination_snapshot()}
	var pressed_callback: Callable = Callable(self,"on_pressed").bind(token,copied.duplicate(true))
	var gui_callback: Callable = Callable(self,"on_gui").bind(token,copied.duplicate(true))
	button.pressed.connect(pressed_callback)
	button.gui_input.connect(gui_callback)
	click_callbacks[token] = {"pressed":pressed_callback,"gui":gui_callback}
	return token

func end_observation(token: String) -> void:
	if token.is_empty() or not clicks.has(token): return
	var button: Button = live_button(int(clicks[token].snapshot.instanceId))
	if button != null:
		var callbacks: Dictionary = click_callbacks.get(token,{})
		if callbacks.has("pressed") and button.pressed.is_connected(callbacks.pressed): button.pressed.disconnect(callbacks.pressed)
		if callbacks.has("gui") and button.gui_input.is_connected(callbacks.gui): button.gui_input.disconnect(callbacks.gui)
	clicks[token]["buttonSurvived"] = button != null
	clicks[token]["after"] = destination_snapshot()
	journal("input_complete",{"token":token,"observation":clicks[token].duplicate(true),"oldButtonSurvivalRequired":false})

func pointer(point: Vector2, pressed: bool, motion: bool, token: String = "") -> void:
	if not bounded(): return
	var event: InputEvent
	if motion:
		event = InputEventMouseMotion.new()
		event.relative = point-pointer_position
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	pointer_position = point
	pointer_left_down = pressed
	if not motion and clicks.has(token):
		var key: String = "pressIssued" if pressed else "releaseIssued"
		clicks[token][key] = int(clicks[token].get(key,0))+1
	var trace: Dictionary = {"token":token,"stage":"motion" if motion else "press" if pressed else "release","position":str(point),"wallSeconds":wall_seconds(),"route":"Viewport.push_input(local=true)","before":destination_snapshot()}
	input_trace.append(trace)
	# Official viewport pipeline: _input -> GUI -> unhandled input. No handler call,
	# no OS cursor warp, and no Input.parse_input_event screen-coordinate ambiguity.
	root.push_input(event,true)
	trace["handledAfterDispatch"] = root.is_input_handled()
	trace["afterDispatch"] = destination_snapshot()
	await settle(1)

func hover_snapshot(id: int, requested_point: Vector2, sample_name: String) -> Dictionary:
	# Retain only copied values across awaits; a destination change may free UI.
	var button: Button = live_button(id)
	var hovered: Control = root.gui_get_hovered_control()
	var mouse_position: Vector2 = root.get_mouse_position()
	var valid_button: bool = button!=null and button.is_visible_in_tree()
	var owns_hover: bool = valid_button and is_instance_valid(hovered) and (hovered==button or button.is_ancestor_of(hovered))
	return {"sample":sample_name,"wallSeconds":wall_seconds(),"drawnFrame":Engine.get_frames_drawn(),"requestedPoint":str(requested_point),"viewportMousePosition":str(mouse_position),"viewportMouseDistancePx":mouse_position.distance_to(requested_point),"mouseMatchesRequestedPoint":mouse_position.distance_to(requested_point)<=1.0,"buttonValid":valid_button,"buttonId":id,"buttonPath":str(button.get_path()) if valid_button else "missing","buttonRect":str(button.get_global_rect()) if valid_button else "missing","requestedPointInsideButton":valid_button and button.get_global_rect().has_point(requested_point),"ownsHover":owns_hover,"hoveredPath":str(hovered.get_path()) if is_instance_valid(hovered) else "none","hoveredClass":hovered.get_class() if is_instance_valid(hovered) else "none","hoveredRect":str(hovered.get_global_rect()) if is_instance_valid(hovered) else "none","hoveredMouseFilter":hovered.mouse_filter if is_instance_valid(hovered) else -1}

func observe_single_motion(id: int, point: Vector2, token: String) -> Dictionary:
	var record: Dictionary = {"token":token,"point":str(point),"motionDispatches":0,"clickDispatches":0,"samples":[],"firstNullPreserved":false,"processedHit":false,"scope":"One motion only. Immediate and two subsequent render-frame observations are retained; no pointer redispatch, click or retry."}
	if not bounded(): return record
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = 0
	input_trace.append({"token":token,"stage":"single_motion_probe","position":str(point),"relative":str(event.relative),"wallSeconds":wall_seconds()})
	record.motionDispatches = 1
	event.relative = point-pointer_position
	pointer_position = point
	root.push_input(event,true)
	record.samples.append(hover_snapshot(id,point,"immediate_after_dispatch"))
	for frame_index in range(2):
		if not bounded(): break
		await RenderingServer.frame_post_draw
		if not bounded(): break
		record.samples.append(hover_snapshot(id,point,"render_frame_"+str(frame_index+1)))
	var last: Dictionary = record.samples[-1]
	record["firstNullPreserved"] = str(record.samples[0].hoveredPath)=="none"
	record["anyNullPreserved"] = record.samples.any(func(row: Dictionary): return str(row.hoveredPath)=="none")
	record["anyUnownedPreserved"] = record.samples.any(func(row: Dictionary): return not bool(row.ownsHover) or not bool(row.mouseMatchesRequestedPoint))
	record["nativePointerMatches"] = bool(last.mouseMatchesRequestedPoint)
	record["processedHit"] = record.samples.size()==3 and bool(last.ownsHover) and bool(last.requestedPointInsideButton)
	record["classification"] = "settled_hit_after_single_motion" if bool(record.processedHit) and bool(record.anyNullPreserved) else "synthetic_hit_native_pointer_differs" if bool(record.processedHit) and not bool(last.mouseMatchesRequestedPoint) else "immediate_and_processed_hit" if bool(record.processedHit) else "processed_null_or_other_owner"
	journal("single_motion_hover",record)
	return record

func stable_center(id: int, token: String) -> Vector2:
	var last: Rect2 = Rect2()
	var stable: int = 0
	var deadline: int = Time.get_ticks_usec()+2500000
	while bounded() and Time.get_ticks_usec()<deadline:
		var button: Button = live_button(id)
		if button == null or button.disabled or not button.is_visible_in_tree(): break
		var ancestor: Node = button.get_parent()
		while ancestor != null and ancestor != root:
			if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
			ancestor = ancestor.get_parent()
		var area: Rect2 = visible_clip(button).intersection(button.get_global_rect())
		button = null
		if not area.has_area():
			await settle(1)
			continue
		await pointer(area.get_center(),false,true,token)
		button = live_button(id)
		if button == null: break
		var now_area: Rect2 = visible_clip(button).intersection(button.get_global_rect())
		var hover: Control = root.gui_get_hovered_control()
		var hovered: bool = is_instance_valid(hover) and (hover == button or button.is_ancestor_of(hover))
		var probe: Dictionary = {"wallSeconds":wall_seconds(),"point":str(area.get_center()),"buttonId":id,"buttonPath":str(button.get_path()),"buttonRect":str(button.get_global_rect()),"clippedRect":str(now_area),"ownsHover":hovered,"hoveredPath":str(hover.get_path()) if is_instance_valid(hover) else "none","hoveredClass":hover.get_class() if is_instance_valid(hover) else "none","hoveredRect":str(hover.get_global_rect()) if is_instance_valid(hover) else "none","hoveredMouseFilter":hover.mouse_filter if is_instance_valid(hover) else -1,"hoveredZIndex":hover.z_index if is_instance_valid(hover) else null,"hoveredSiblingIndex":hover.get_index() if is_instance_valid(hover) else -1}
		if not hover_probes.has(token): hover_probes[token] = {"attempts":0,"samples":[],"last":{}}
		hover_probes[token].attempts = int(hover_probes[token].attempts)+1
		if hover_probes[token].samples.size()<12: hover_probes[token].samples.append(probe.duplicate(true))
		hover_probes[token].last = probe
		stable = stable+1 if area == now_area and area == last and hovered else 0
		last = now_area
		button = null
		hover = null
		if stable>=2: return now_area.get_center()
	if hover_probes.has(token): journal("hover_precondition_failed",hover_probes[token])
	check(false,"Input observer could not obtain stable first-click geometry: "+token)
	return Vector2(NAN,NAN)

func click_id(id: int, note: String, expects_pressed: bool = true) -> bool:
	var token: String = begin_observation(id,note)
	if token.is_empty(): return false
	var center: Vector2 = await stable_center(id,token)
	if not center.is_finite(): end_observation(token); return false
	clicks[token].dispatchCount = 1
	await pointer(center,true,false,token)
	# A successful action may delete its button; release uses copied coordinates.
	await pointer(center,false,false,token)
	await settle(2)
	end_observation(token)
	check(int(clicks[token].pressIssued)==1 and int(clicks[token].releaseIssued)==1,note+": exactly one press/release pair issued")
	# Successful actions may free the button during release; token callbacks keep
	# only copied metadata. Missing receipt remains visible even if it was freed.
	return check(int(clicks[token].pressedSignals) == 1,note+": first click delivered one pressed signal") if expects_pressed else true

func key_enter() -> void:
	for pressed in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		root.push_input(event,true)
		input_trace.append({"stage":"home_enter","pressed":pressed,"wallSeconds":wall_seconds()})
		await settle(1)

func capture(label_value: String, analysis_only: bool = false) -> void:
	if not alive(): return
	measurement_epoch += 1
	await settle(1)
	if not alive(): return
	var image: Image = root.get_texture().get_image()
	var path: String = output_dir.path_join(label_value+".png")
	var error: Error = image.save_png(path)
	captures.append({"label":label_value,"path":ProjectSettings.globalize_path(path),"width":image.get_width(),"height":image.get_height(),"saveError":error,"clock":app.game.elapsed,"phase":phase,"qaAnalysisOnly":analysis_only,"acceptedArtCapture":false if analysis_only else null})
	check(error == OK,"Actual uncropped viewport capture saved: "+label_value)
	journal("capture",captures[-1])
	measurement_epoch += 1

func resize(dimensions: Vector2i) -> void:
	measurement_epoch += 1
	root.size = dimensions
	root.content_scale_size = dimensions
	await settle(5)
	measurement_epoch += 1

func on_event(event: Dictionary) -> void:
	if str(event.get("type","")) == "footstep": return
	var copied: Dictionary = event.duplicate(true)
	copied["qaWallSeconds"] = wall_seconds()
	events.append(copied)
	if str(event.get("type","")) in ["recruitment_queued","placed","recruited","hit","shot","swing","killed"]:
		journal("game_event",copied)

func observe_ingress() -> void:
	if not alive(): return
	for enemy in app.game.enemies:
		var id: String = str(enemy.id)
		var position: Vector2 = enemy.position
		var visible_foot: bool = Rect2(Vector2.ZERO,Vector2.ONE).has_point(position)
		if not ingress.has(id):
			ingress[id] = {"id":int(enemy.id),"kind":str(enemy.kind),"firstPosition":str(position),"firstClock":app.game.elapsed,"firstOutsideMap":not visible_foot,"enteredMap":false,"firstHp":enemy.hp,"lowestHp":enemy.hp,"samples":[],"lastSampleWall":-1.0,"lastPosition":position,"largestFrameStep":0.0}
		var trace: Dictionary = ingress[id]
		trace.largestFrameStep = maxf(float(trace.largestFrameStep),position.distance_to(trace.lastPosition))
		trace.lastPosition = position
		trace.lowestHp = minf(float(trace.lowestHp),float(enemy.hp))
		if visible_foot and not bool(trace.enteredMap):
			trace.enteredMap = true
			trace.entryClock = app.game.elapsed
			trace.entryPosition = str(position)
			journal("same_enemy_entered",{"id":id,"startedOutside":trace.firstOutsideMap,"position":str(position),"clock":app.game.elapsed})
		if wall_seconds()-float(trace.lastSampleWall) >= .4 and trace.samples.size()<150:
			trace.samples.append({"wallSeconds":wall_seconds(),"clock":app.game.elapsed,"position":str(position),"screenFoot":str(app.game.field_point_to_screen(position)),"outsideMap":not visible_foot,"hp":enemy.hp,"animation":enemy.get("animation","walk"),"ingressActive":enemy.get("ingressActive",false)})
			trace.lastSampleWall = wall_seconds()

func eligible_now() -> bool:
	if not alive() or not measuring or phase != "natural_combat": return false
	return live_battle() and app.game.units.size()>0 and app.game.enemies.size()>0

func observe_frames() -> void:
	var previous: int = Time.get_ticks_usec()
	var previous_eligible: bool = false
	var previous_epoch: int = measurement_epoch
	var previous_clock: float = 0.0
	var rid: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	while observing and bounded():
		await RenderingServer.frame_post_draw
		if not observing or not alive(): break
		var now: int = Time.get_ticks_usec()
		var destination: String = "context" if app.context_task_active else str(app.modal_context) if app.modal!=null else "battle" if app.battle_started else "home"
		if destination!=previous_destination:
			if destination_visits.has(destination): destination_visits[destination] = int(destination_visits[destination])+1
			journal("destination",{"from":previous_destination,"to":destination,"clock":app.game.elapsed})
			previous_destination = destination
		observe_ingress()
		if live_battle() and app.game.elapsed>previous_clock:
			for actor_key in app.game.painted_actors.actor_samples:
				var sample: Dictionary=app.game.painted_actors.actor_samples[actor_key]
				var signature: String=JSON.stringify([sample.get("renderState",""),sample.get("sourceDirection",""),sample.get("sourceFrame",-1),sample.get("releaseEventId",-1),sample.get("rigJoints",{}),sample.get("walkPhase",-1)])
				if str(action_keys.get(actor_key,""))==signature or action_trace.size()>=3000: continue
				action_keys[actor_key]=signature
				action_trace.append({"actorKey":actor_key,"clock":app.game.elapsed,"wallSeconds":wall_seconds(),"sample":sample.duplicate(true)})
		var eligible: bool = eligible_now()
		if eligible and previous_eligible and previous_epoch == measurement_epoch and app.game.elapsed>previous_clock:
			var ms: float = float(now-previous)/1000.0
			var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
			frame_rows.append({"frameMs":ms,"wallSeconds":wall_seconds(),"clock":app.game.elapsed,"friendly":app.game.units.size(),"enemies":app.game.enemies.size(),"drawCalls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"gpuMs":gpu if gpu>0.0 else null})
			eligible_wall_seconds += ms/1000.0
		previous = now
		previous_eligible = eligible
		previous_epoch = measurement_epoch
		previous_clock = app.game.elapsed

func queued_since(index: int, type_name: String) -> Array:
	return events.slice(index).filter(func(event: Dictionary): return str(event.get("type",""))=="recruitment_queued" and str(event.get("unitType",""))==type_name)

func drag_archer(zone_id: String) -> bool:
	if not alive(): return false
	var zone_position: Vector2 = Vector2(NAN,NAN)
	for zone in app.game.zones:
		if str(zone.get("id","")) == zone_id: zone_position = zone.position; break
	if not check(zone_position.is_finite(),"Actual painted firing deck exists: "+zone_id): return false
	var cost: int = app.game.recruit_cost("archer")
	if app.game.gold<cost:
		incomplete.append("Second archer not affordable from natural funds: "+zone_id)
		return false
	var id: int = card_id("archer")
	var token: String = begin_observation(id,"Paid archer drag "+zone_id)
	if token.is_empty(): return false
	var origin: Vector2 = await stable_center(id,token)
	if not alive() or not origin.is_finite(): end_observation(token); return false
	var target: Vector2 = app.game.field_point_to_screen(zone_position)
	var before: int = events.size()
	var gold_before: int = app.game.gold
	clicks[token].dispatchCount = 1
	await pointer(origin,true,false,token)
	await pointer(origin.lerp(target,.3),true,true,token)
	await pointer(target,true,true,token)
	if not alive(): end_observation(token); return false
	var preview: Dictionary = app.deployment_drag.get("preview",{}).duplicate(true)
	await pointer(target,false,false,token)
	await settle(2)
	end_observation(token)
	if not alive(): return false
	var receipts: Array = queued_since(before,"archer")
	paid_orders.append({"unitType":"archer","zone":zone_id,"token":token,"preview":preview,"goldBefore":gold_before,"goldAfter":app.game.gold,"receipts":receipts})
	return check(receipts.size()==1 and int(receipts[0].cost)==cost,"One real drag queues and pays one archer order on "+zone_id)

func spear_order() -> bool:
	if not alive(): return false
	if app.game.gold<app.game.recruit_cost("spear"):
		incomplete.append("Spear order not affordable from natural funds")
		return false
	var before: int = events.size()
	var wallet: int = app.game.gold
	await click_id(card_id("spear"),"Paid spear card first click",false)
	if not alive(): return false
	var receipts: Array = queued_since(before,"spear")
	paid_orders.append({"unitType":"spear","goldBefore":wallet,"goldAfter":app.game.gold,"receipts":receipts})
	return check(receipts.size()==1,"One real spear-card click queues one marching order")

func hud_evidence() -> Dictionary:
	var result: Dictionary = {}
	for property_name in ["map_title","hud_clock","hud_gold","hud_health","hud_capacity","learning_caption"]:
		var control: Variant = app.get(property_name)
		if is_instance_valid(control) and control is Control:
			result[property_name] = {"visible":control.is_visible_in_tree(),"text":str(control.get("text")),"rect":str(control.get_global_rect())}
	if is_instance_valid(app.active_word): result["activeWord"] = {"visible":app.active_word.is_visible_in_tree(),"word":app.active_word.word.duplicate(true),"rect":str(app.active_word.get_global_rect())}
	return result

func named_control(parent: Node, node_name: String) -> Control:
	return parent.find_child(node_name,true,false) as Control if is_instance_valid(parent) else null

func compact_text(value: String) -> String:
	return value.replace(" ","").replace("\n","").replace("\r","").replace("\t","")

func paired_text_check(layout: Dictionary, expected: Dictionary, transform: Transform2D, clip: Rect2, label_value: String) -> Dictionary:
	var body: String = ""
	var meaning: String = ""
	var body_bounds: Rect2 = Rect2()
	var meaning_bounds: Rect2 = Rect2()
	var body_count: int = 0
	var meaning_count: int = 0
	var reading_count: int = 0
	var all_visible: bool = true
	var runs: Array = []
	for run in layout.get("runs",[]):
		var bounds: Rect2 = transform*Rect2(run.bounds)
		var role: String = str(run.get("role",""))
		all_visible = all_visible and clip.grow(1.5).encloses(bounds)
		if role=="body":
			body += str(run.text)
			body_bounds = bounds if body_count==0 else body_bounds.merge(bounds)
			body_count += 1
		elif role=="meaning":
			meaning += str(run.text)
			meaning_bounds = bounds if meaning_count==0 else meaning_bounds.merge(bounds)
			meaning_count += 1
		elif role=="reading": reading_count += 1
		runs.append({"role":role,"text":str(run.text),"fontSize":run.get("size",0),"screenBounds":str(bounds)})
	var complete_japanese: bool = not str(expected.get("jp","")).is_empty() and compact_text(body)==compact_text(str(expected.get("jp","")))
	var complete_korean: bool = not str(expected.get("ko","")).is_empty() and compact_text(meaning)==compact_text(str(expected.get("ko","")))
	var gap: float = meaning_bounds.position.y-body_bounds.end.y if body_count>0 and meaning_count>0 else INF
	check(complete_japanese,label_value+": complete Japanese exists in the actual text runs")
	check(complete_korean,label_value+": complete Korean exists in the same text block")
	check(body_count>0 and meaning_count>0 and gap>=0 and gap<=6.0,label_value+": Korean sits immediately below the final Japanese line without overlap")
	check(all_visible and not runs.is_empty(),label_value+": every Japanese, reading and Korean run fits inside the actual clip")
	if not str(expected.get("reading","")).is_empty(): check(reading_count>0,label_value+": reading guides are present")
	return {"expectedWord":expected.duplicate(true),"japanese":body,"korean":meaning,"japaneseBounds":str(body_bounds),"koreanBounds":str(meaning_bounds),"gapPx":gap if is_finite(gap) else null,"readingRuns":reading_count,"allRunsVisible":all_visible,"runs":runs,"scope":"Measured runs used by the actual renderer; unannotated capture remains the visual evidence."}

func briefing_check(label_value: String) -> void:
	if not alive(): return
	var paper: Control = named_control(app.modal,"MissionBriefingPaper")
	if not check(is_instance_valid(paper),label_value+": actual mission briefing paper is mounted"): return
	var paper_rect: Rect2 = paper.get_global_rect()
	check(paper_rect.size.x/maxf(1,paper_rect.size.y)>=2.0 and root.get_visible_rect().encloses(paper_rect),label_value+": briefing is wide and fully inside the viewport")
	check(is_zero_approx(app.game.elapsed) and not app.battle_started and (not app.game.running or app.game.paused),label_value+": simulation remains at zero until mission confirmation")
	var enemy_profile: Dictionary = app.current_map.get("enemyModeProfile",{})
	var assigned_mode: String = str(enemy_profile.get("id",app.current_map.get("mode","")))
	var rows: Dictionary = {"paper":str(paper_rect),"clock":app.game.elapsed,"automaticallyAssignedMode":assigned_mode,"scenarioMode":str(app.current_map.get("mode","")),"enemyModeProfile":enemy_profile.duplicate(true),"stageId":str(app.current_map.get("id","")),"stageNumber":int(app.current_map.get("stageNumber",0)),"controls":[],"textRuns":[]}
	var scroll: ScrollContainer = app.modal_scroll
	var vertical_range: float = scroll.get_v_scroll_bar().max_value-scroll.get_v_scroll_bar().page
	var horizontal_range: float = scroll.get_h_scroll_bar().max_value-scroll.get_h_scroll_bar().page
	rows["scrollRange"] = {"vertical":vertical_range,"horizontal":horizontal_range,"currentVertical":scroll.scroll_vertical}
	check(vertical_range<=2 and horizontal_range<=2 and scroll.scroll_vertical==0,label_value+": full briefing fits without scrolling")
	for name_value in ["MissionHeading","MissionInstruction","InstructionHints","ScenarioAssignment","ModeInstructions","ConfirmMission"]:
		var control: Control = named_control(app.modal,name_value)
		var visible: bool = is_instance_valid(control) and control.is_visible_in_tree()
		check(visible and visible_clip(control).grow(1).encloses(control.get_global_rect()),label_value+": full briefing control is visible: "+name_value)
		if visible: rows.controls.append({"name":name_value,"rect":str(control.get_global_rect()),"text":str(control.get("text")) if control is Label or control is Button else ""})
	var mission: Control = named_control(app.modal,"MissionInstruction")
	if is_instance_valid(mission):
		var word: Dictionary = mission.get("word")
		var layout: Dictionary = mission.call("get_text_layout")
		var body: String = ""
		var meaning: String = ""
		var reading_count: int = 0
		var all_runs_visible: bool = true
		for run in layout.get("runs",[]):
			var bounds: Rect2 = run.bounds
			bounds.position += mission.get_global_rect().position
			all_runs_visible = all_runs_visible and visible_clip(mission).grow(1.5).encloses(bounds)
			if str(run.role)=="body": body += str(run.text)
			elif str(run.role)=="meaning": meaning += str(run.text)
			elif str(run.role)=="reading": reading_count += 1
			rows.textRuns.append({"role":run.role,"text":run.text,"fontSize":run.get("size",0),"screenBounds":str(bounds)})
		check(not str(word.get("jp","")).is_empty() and compact_text(body)==compact_text(str(word.get("jp",""))),label_value+": complete mission Japanese is present in actual text runs")
		check(not str(word.get("ko","")).is_empty() and compact_text(meaning)==compact_text(str(word.get("ko",""))),label_value+": complete Korean mission meaning is present in actual text runs")
		check(reading_count>0 and not str(word.get("reading","")).is_empty(),label_value+": mission has rendered reading guides and reading data")
		check(all_runs_visible,label_value+": every Japanese, reading and Korean mission text run is within the actual clip")
		rows["missionWord"] = word.duplicate(true)
	rows["translationPairs"] = {}
	for name_value in ["MissionHeading","MissionInstruction"]:
		var translated: Control = named_control(app.modal,name_value)
		if not check(is_instance_valid(translated) and translated.has_method("get_text_layout"),label_value+": paired Japanese/Korean control exists: "+name_value): continue
		rows.translationPairs[name_value] = paired_text_check(translated.call("get_text_layout"),translated.get("word"),translated.get_global_transform_with_canvas(),visible_clip(translated).intersection(translated.get_global_rect()),label_value+" "+name_value)
	var selector: Control = named_control(app.modal,"CombatModeSelector")
	check(not is_instance_valid(selector) or not selector.is_visible_in_tree(),label_value+": historical scenario has no player combat-mode selector")
	for mode in ["defense","onslaught","siege"]:
		var mode_button: Control = named_control(app.modal,"CombatMode_"+mode)
		check(not is_instance_valid(mode_button) or not mode_button.is_visible_in_tree(),label_value+": obsolete mode button is absent: "+mode)
	var scenario_label: Control = named_control(app.modal,"ScenarioAssignment")
	if not is_instance_valid(scenario_label): scenario_label = named_control(app.modal,"ModeInstructions")
	check(is_instance_valid(scenario_label) and scenario_label.is_visible_in_tree() and visible_clip(scenario_label).grow(1).encloses(scenario_label.get_global_rect()),label_value+": automatically assigned scenario instruction is visible")
	check(not assigned_mode.is_empty(),label_value+": loaded historical stage records its automatic combat mode")
	rows["scenarioInstruction"] = str(scenario_label.get("text")) if is_instance_valid(scenario_label) else "missing"
	rows["modeScope"] = "This actual first historical scenario assigns combat mode automatically. No player mode selection, and no claim that all40scenarios were played."
	if not evidence.has("briefing"): evidence["briefing"] = {}
	evidence.briefing[label_value] = rows
	journal("briefing",rows)

func screen_luma(image: Image, point: Vector2) -> float:
	var color: Color = image.get_pixel(clampi(roundi(point.x),0,image.get_width()-1),clampi(roundi(point.y),0,image.get_height()-1))
	return color.r*.2126+color.g*.7152+color.b*.0722

func compact_ui_check(label_value: String) -> void:
	if not alive(): return
	var screen: Rect2 = root.get_visible_rect()
	var rows: Dictionary = {"resolution":str(root.size),"clock":app.game.elapsed,"captions":[],"cards":[],"studyHover":[]}
	for property_name in ["map_title","hud_clock","hud_gold","hud_health"]:
		var required: Control = app.get(property_name) as Control
		check(is_instance_valid(required) and required.is_visible_in_tree() and screen.grow(1).encloses(required.get_global_rect()),label_value+": required HUD is visible and inside the viewport: "+property_name)
	for property_name in ["active_word","narration_subtitle","announcement_subtitle"]:
		var control: Control = app.get(property_name) as Control
		if not is_instance_valid(control): continue
		var rect: Rect2 = control.get_global_rect()
		var visible: bool = control.is_visible_in_tree()
		rows.captions.append({"name":property_name,"visible":visible,"rect":str(rect),"baseSize":control.get("base_size"),"word":control.get("word")})
		if visible:
			var size_limit: int = 28 if property_name=="active_word" else 20
			check(int(control.get("base_size"))<=size_limit and rect.size.y<=app.game.field_rect.size.y*.28,label_value+": visible caption uses compact type and height: "+property_name)
			check(screen.grow(1).encloses(rect),label_value+": visible caption is not outside the viewport: "+property_name)
	var framebuffer: Image = root.get_texture().get_image()
	for card in app.army_grid.get_children():
		if not card is Button or not card.is_visible_in_tree(): continue
		var rect: Rect2 = card.get_global_rect()
		var locked: bool = bool(card.get_meta("hud_locked",false))
		var sampled: Array = []
		for uv in [Vector2(.06,.40),Vector2(.94,.40),Vector2(.06,.65),Vector2(.94,.65),Vector2(.14,.84),Vector2(.88,.84)]:
			sampled.append(screen_luma(framebuffer,rect.position+rect.size*uv))
		var portrait: TextureRect
		for child in card.get_children():
			if child is TextureRect: portrait = child; break
		var p75: float = float(percentile(sampled,.75))
		var has_portrait: bool = is_instance_valid(portrait) and portrait.texture!=null and portrait.is_visible_in_tree()
		check(p75>=(.30 if locked else .45),label_value+": rendered card background is bright enough to separate its thumbnail: "+str(card.name))
		check(has_portrait,label_value+": actual card thumbnail texture is mounted: "+str(card.name))
		rows.cards.append({"name":str(card.name),"rect":str(rect),"locked":locked,"visibleClip":str(visible_clip(card)),"framebufferSrgbLumaSamples":sampled,"framebufferSrgbLumaP75":p75,"thumbnailMounted":has_portrait,"portraitModulate":str(portrait.modulate) if has_portrait else "missing","note":"Sparse rendered background contrast proxy; detailed painted-body quality still needs visual review."})
	framebuffer = null
	var id: int = property_button_id("battle_study_button")
	var center: Vector2 = await stable_center(id,"layout-only-study-"+label_value)
	if not alive(): return
	var button: Button = live_button(id)
	if not check(button != null and button.is_visible_in_tree() and center.is_finite(),label_value+": study button is visible and reaches hover without clicking"):
		if not evidence.has("compactUI"): evidence["compactUI"] = {}
		evidence.compactUI[label_value] = rows
		return
	var rect: Rect2 = button.get_global_rect()
	check(screen.grow(1).encloses(rect),label_value+": entire study button is inside the viewport")
	button = null
	for uv in [Vector2(.5,.5),Vector2(.12,.16),Vector2(.88,.16),Vector2(.12,.84),Vector2(.88,.84)]:
		var point: Vector2 = rect.position+rect.size*uv
		var observation: Dictionary = await observe_single_motion(id,point,"book-region-"+label_value+"-"+str(uv))
		if not alive(): return
		rows.studyHover.append(observation)
		check(bool(observation.processedHit),label_value+": study button receives pointer after normal event processing at "+str(uv))
	if not evidence.has("compactUI"): evidence["compactUI"] = {}
	evidence.compactUI[label_value] = rows
	journal("compact_ui",rows)

func foot_registration_diagnostics(label_value: String) -> void:
	if not alive(): return
	var renderer: Variant = app.game.painted_actors
	var rows: Array = []
	var images: Dictionary = {}
	var alpha_cache: Dictionary = {}
	var height: float = renderer.body_height_screen*clampf(app.game.field_rect.size.y/620.0,.65,1.5)
	# This reads the active renderer's already-selected items/pose lookup. It
	# neither calls gameplay handlers nor poses/moves actors for the evidence.
	for item in renderer.get("_items"):
		var actor: Dictionary = item.actor
		var state: String = str(actor.get("animation","idle"))
		var direction: String = renderer._direction_name(item.direction,item.friendly)
		var animation: Dictionary = renderer._animation(item.type_name,item.friendly,direction,state)
		var pose: Variant = renderer._pose(animation,state,maxf(0,float(actor.get("animationClock",0))),float(actor.get("animationPhase",0)))
		if pose==null: continue
		var texture_id: int = pose.texture.get_instance_id()
		if not images.has(texture_id): images[texture_id] = pose.texture.get_image()
		var source: Image = images[texture_id]
		var key: String = str(texture_id)+":"+str(pose.region)
		if not alpha_cache.has(key):
			var bottom: int = -1
			var solid_x: Array = []
			var region: Rect2i = Rect2i(pose.region)
			for y in range(region.size.y-1,maxi(-1,int(region.size.y*.65)),-1):
				for x in range(0,region.size.x,2):
					if source.get_pixel(region.position.x+x,region.position.y+y).a>=.35: solid_x.append(x)
				if not solid_x.is_empty(): bottom = y; break
			alpha_cache[key] = {"lowestOpaqueLocalY":bottom,"lowestRowOpaqueMedianX":percentile(solid_x,.5),"lowerRowsSearchStart":int(region.size.y*.65),"alphaThreshold":.35,"xStride":2}
		var alpha: Dictionary = alpha_cache[key]
		var scale_value: float = height/pose.body_height
		rows.append({"id":actor.get("id",-1),"side":"friendly" if item.friendly else "enemy","type":item.type_name,"state":state,"direction":direction,"modelPosition":str(actor.position),"actualRenderOrigin":str(app.game.field_point_to_screen(actor.position)),"sourceRegion":str(pose.region),"sourceAnchor":str(pose.anchor),"sourceOffset":str(pose.offset),"bodyHeightPixels":pose.body_height,"sourceToScreenScale":scale_value,"alphaEdge":alpha.duplicate(true),"opaqueLowerEdgeDeltaFromAnchorScreenPx":(float(alpha.lowestOpaqueLocalY)-pose.anchor.y+pose.offset.y)*scale_value if int(alpha.lowestOpaqueLocalY)>=0 else null,"scope":"Registration proxy only. Lowest alpha can be a weapon, cloth or hoof. Excludes animated lift/attack rotation; not anatomical sole contact verification."})
	var record: Dictionary = {"clock":app.game.elapsed,"resolution":str(root.size),"actors":rows,"rendererDiagnostics":renderer.diagnostics(),"registrationProxy":"Source-frame alpha edge versus configured foot anchor; actual live origin recorded independently","observedFootContact":{"status":"manual_frame_review_required","evidence":"See normal unannotated captures in this run. QA does not count an anchor/shadow setting as visible contact acceptance."}}
	if not evidence.has("footGrounding"): evidence["footGrounding"] = {}
	evidence.footGrounding[label_value] = record
	journal("foot_registration",record)

func road_overlay_capture() -> void:
	if not alive() or not FileAccess.file_exists(ROAD_EVIDENCE): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROAD_EVIDENCE))
	if not parsed is Dictionary: return
	phase = "qa_analysis_overlay"
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 110
	var overlay = RoadOverlay.new()
	root.add_child(layer)
	layer.add_child(overlay)
	overlay.configure(app.game,parsed)
	await settle(2)
	if alive():
		await capture("qa-analysis-road-and-foot-origins-1280x800",true)
		if is_instance_valid(overlay): evidence["roadOverlay"] = overlay.diagnostics()
	if is_instance_valid(layer): layer.queue_free()
	await settle(1)

func visible_ingress_enemy() -> Dictionary:
	if not alive(): return {}
	for enemy in app.game.enemies:
		var trace: Dictionary = ingress.get(str(enemy.id),{})
		var point: Vector2 = enemy.position
		if bool(trace.get("firstOutsideMap",false)) and point.x<=.985 and point.x>=0 and point.y>=.025 and point.y<1:
			return {"id":enemy.id,"kind":enemy.kind,"clock":app.game.elapsed,"position":str(point),"screenFoot":str(app.game.field_point_to_screen(point)),"firstOutsidePosition":trace.get("firstPosition",""),"firstClock":trace.get("firstClock",null)}
	return {}

func selected_translation_check(label_value: String) -> void:
	if not alive(): return
	if not evidence.has("selectedTranslation"): evidence["selectedTranslation"] = {}
	var selected: Dictionary = {}
	for unit in app.game.units:
		if int(unit.id)==int(app.game.selected_id) and float(unit.hp)>0:
			selected = unit.duplicate(true)
			break
	if selected.is_empty():
		evidence.selectedTranslation[label_value] = {"status":"no_surviving_selected_unit","scope":"No replacement unit selected for QA."}
		return
	var layout: Dictionary = app.game.selected_unit_label_layout(selected)
	var canvas: Node2D = app.game.actor_overlay
	var clip: Rect2 = canvas.get_global_transform_with_canvas()*Rect2(app.game.visible_field_rect_local())
	clip = clip.intersection(root.get_visible_rect())
	clip = clip.intersection(canvas.get_global_transform_with_canvas()*Rect2(layout.rect))
	var expected: Dictionary = {"jp":str(selected.get("jp","")),"reading":str(selected.get("reading","")),"ko":str(selected.get("name",""))}
	var rows: Dictionary = paired_text_check(layout,expected,canvas.get_global_transform_with_canvas(),clip,label_value+" selected soldier label")
	rows["unitId"] = selected.id
	rows["drawnInCurrentState"] = bool(app.game._selected_name_visible(selected)) and canvas.is_visible_in_tree()
	rows["animation"] = selected.get("animation","")
	rows["combatState"] = selected.get("combatState","")
	if not bool(rows.drawnInCurrentState): rows["scope"] = "Computed draw layout only: the product currently hides selected names in this combat state; this does not establish visible text acceptance."
	evidence.selectedTranslation[label_value] = rows
	journal("selected_translation",rows)

func selection_check() -> void:
	phase = "selection"
	check(int(app.game.explicit_selection_id)==-1 and not app.army_panel.is_visible_in_tree(),"Recruitment does not open an inspector before an explicit battlefield selection")
	var selected: Dictionary = {}
	for unit in app.game.units:
		if str(unit.type)=="archer" and float(unit.hp)>0: selected = unit.duplicate(true); break
	if not check(not selected.is_empty(),"A naturally produced archer remains available for selection"): return
	var target: Vector2 = app.game.field_point_to_screen(selected.position)
	await pointer(target,false,true)
	await pointer(target,true,false)
	await pointer(target,false,false)
	await settle(2)
	if not alive(): return
	check(int(app.game.selected_id)==int(selected.id),"Actual battlefield click selects the intended live soldier")
	check(int(app.game.explicit_selection_id)==int(selected.id),"Actual field click records an explicit selection instead of incidental auto-selection")
	check(int(app.inspector_unit_id)==int(selected.id) and app.army_panel.is_visible_in_tree(),"Selected live soldier reaches the actual HUD inspector")
	var current_hp: float = -1.0
	for unit in app.game.units:
		if int(unit.id)==int(selected.id): current_hp = float(unit.hp); break
	check(app.army_health.is_visible_in_tree() and current_hp>=0 and absf(float(app.army_health.value)-current_hp)<.1,"Selected soldier's displayed health agrees with its actual live HP")
	evidence["selection"] = {"requestedId":selected.id,"selectedId":app.game.selected_id,"explicitSelectionId":app.game.explicit_selection_id,"inspectorId":app.inspector_unit_id,"healthVisible":app.army_health.is_visible_in_tree(),"healthValue":app.army_health.value,"healthMax":app.army_health.max_value,"label":app.selected_label.text}
	await capture("selected-live-unit-1440x900")
	selected_translation_check("selected-live-unit-1440x900")

func pause_and_learning() -> void:
	phase = "pause"
	var clock_before: float = app.game.elapsed
	await click_id(property_button_id("pause_button"),"Pause first click")
	if not alive(): return
	if not check(app.game.paused,"Pause destination state is reached on the first click"):
		incomplete.append("Learning/return not attempted after first-click pause failure; no second-click workaround")
		return
	var paused_clock: float = app.game.elapsed
	await settle(6)
	if not alive(): return
	check(is_equal_approx(app.game.elapsed,paused_clock),"Paused natural simulation clock does not advance")
	await capture("paused-1440x900")
	if not alive(): return
	await click_id(property_button_id("pause_button"),"Resume first click")
	if not alive(): return
	if not check(not app.game.paused,"Resume destination state is reached on the first click"):
		incomplete.append("Learning/return not attempted after first-click resume failure; no repeat input")
		return
	check(await wait_until(func(): return alive() and app.game.elapsed>paused_clock,.7),"Natural simulation resumes after the first resume click")
	if not alive(): return
	evidence["pause"] = {"before":clock_before,"pausedClock":paused_clock,"afterResume":app.game.elapsed}
	phase = "learning"
	await click_id(property_button_id("battle_study_button"),"Learning panel first click")
	if not alive(): return
	if not check(app.modal != null and app.modal_context=="study","Actual learning button opens the study destination"): return
	evidence["study"] = {"opened":true,"paused":app.game.paused,"clock":app.game.elapsed}
	await capture("learning-panel-1440x900")
	if not alive(): return
	check(is_equal_approx(app.game.elapsed,float(evidence.study.clock)),"Manual study keeps the actual battle clock frozen until return")
	var back_id: int = visible_button_text(app.modal,"전장으로 돌아가기")
	if back_id == 0: back_id = visible_button_text(app.modal,"전투로 복귀")
	await click_id(back_id,"Learning return first click")
	if not alive(): return
	check(await wait_until(func(): return alive() and app.modal == null and not app.game.paused,2.0),"Learning first return click restores the live battle")
	if not alive(): return
	evidence.study["returned"] = app.modal == null and not app.game.paused
	await capture("learning-return-1440x900")
	if not alive(): return

func automatic_learning_return() -> void:
	phase = "automatic_learning_wait"
	var arrived: bool = await wait_until(func(): return alive() and app.context_task_active and str(app.modal_context)=="context",18.0)
	if not alive(): return
	if not check(arrived,"Natural battle progression opens the automatic contextual learning destination"):
		incomplete.append("Automatic contextual learning was not reached within the bounded observation")
		return
	# Observe the normal entrance animation; a disabled/in-transition control is
	# not an actionable first click. Never call its gameplay callback directly.
	var actionable: bool = await wait_until(func(): return alive() and app.context_task_active and is_instance_valid(app.learning_transition) and app.learning_transition.accepts_actions() and is_instance_valid(app.learning_field.continue_button) and app.learning_field.continue_button.is_visible_in_tree() and not app.learning_field.continue_button.disabled,3.0)
	if not alive(): return
	if not check(actionable,"Automatic contextual learning finishes its entrance and exposes an enabled return button"):
		await capture("automatic-learning-unready")
		if not alive(): return
		return
	phase = "automatic_learning"
	var paused_clock: float = app.game.elapsed
	evidence["automaticLearning"] = {"opened":true,"clock":paused_clock,"context":str(app.modal_context),"transition":str(app.learning_transition.phase),"betweenWaves":app.game.between_waves,"inputEnabled":app.game.input_enabled}
	await capture("automatic-learning-1280x800")
	if not alive(): return
	var button_id: int = visible_button_text(app.learning_field,"건너뛰고 전투 복귀")
	await click_id(button_id,"Automatic contextual learning skip and return first click")
	if not alive(): return
	var returned: bool = await wait_until(func(): return alive() and not app.context_task_active and app.modal == null and not app.game.paused and not app.game.between_waves and app.game.input_enabled and not app.learning_transition.is_busy(),3.0)
	if not alive(): return
	check(returned,"First contextual skip/return click restores the actual running battle")
	evidence.automaticLearning["returned"] = returned
	evidence.automaticLearning["returnClock"] = app.game.elapsed
	evidence.automaticLearning["transitionAfter"] = str(app.learning_transition.phase)
	if returned:
		check(await wait_until(func(): return alive() and app.game.elapsed>paused_clock,.8),"Natural battle clock advances after contextual learning return")
		if not alive(): return
	await capture("automatic-learning-return-1280x800")
	if not alive(): return
	if not returned:
		incomplete.append("First automatic return failed; subsequent motion capture and answer checks stopped, no retry")
		return
	await capture_action_sequence()
	if not alive(): return
	await automatic_correct_reward()
	if not alive(): return

func automatic_correct_reward() -> void:
	phase = "automatic_correct_wait"
	if not check(await wait_until(func(): return alive() and app.context_task_active and is_instance_valid(app.learning_transition) and app.learning_transition.accepts_answers(),30.0),"A separate natural contextual task opens for the answer/reward path"):
		incomplete.append("Second natural task not reached; reward path unverified")
		return
	await capture("automatic-answer-choice-1280x800")
	if not alive(): return
	learning_choice_audit("1280x800")
	await resize(Vector2i(1440,900))
	if not alive(): return
	await capture("automatic-answer-choice-1440x900")
	if not alive(): return
	learning_choice_audit("1440x900")
	await resize(Vector2i(1280,800))
	if not alive(): return
	var attempt_id: String=str(app.quiz_task.get("id",""))
	var answer: String = str(app.learning_field.correct_target)
	var chosen_id: int = 0
	var targets: Array = app.learning_field.mission.get("targets",[])
	for index in range(mini(targets.size(),app.learning_field.target_buttons.size())):
		if str(targets[index].get("id",""))==answer:
			var value: Variant = app.learning_field.target_buttons[index]
			if is_instance_valid(value): chosen_id = value.get_instance_id()
	# The answer ID is read for deterministic QA; submission is one real GUI click.
	var before: int = events.size()
	if not await click_id(chosen_id,"Separate contextual correct answer first click"): return
	if not check(await wait_until(func(): return alive() and app.quiz_resolved and app.learning_transition.accepts_actions(),3.0),"Correct answer reaches a settled result"):
		return
	var receipts: Array = events.slice(before).filter(func(row: Dictionary): return str(row.get("type",""))=="learning-reward-receipt" and str(row.get("receipt",{}).get("attemptId",""))==attempt_id)
	check(not receipts.is_empty(),"Normal correct answer emits a structured reward receipt")
	var receipt_id: String=str(receipts[0].get("receipt",{}).get("receiptId","")) if not receipts.is_empty() else ""
	check(not receipt_id.is_empty(),"Correct answer has its own receipt ID")
	evidence["correctReward"] = {"answerReadForQA":true,"attemptId":attempt_id,"receiptId":receipt_id,"submission":"actual_gui_first_click","eventsBeforeReturn":receipts.duplicate(true),"snapshotBeforeReturn":app.game.snapshot().get("learningRewardReceipts",[])}
	await capture("correct-answer-reward-notice-1280x800")
	if not alive(): return
	visible_ui_audit(app.ui,"correct-answer-result")
	if not alive(): return
	var back_id: int = visible_button_text(app.learning_field,"전투로 복귀")
	var prior_clock: float = app.game.elapsed
	if not await click_id(back_id,"Correct result return first click"): return
	var returned: bool = await wait_until(func(): return live_battle() and app.game.elapsed>prior_clock,4.0)
	if not alive(): return
	check(returned,"Correct-result first return restores battle and advances its clock")
	if not returned: return
	var delivered: bool = await wait_until(func():
		if not live_battle(): return false
		for row in app.game.snapshot().get("learningRewardReceipts",[]):
			if str(row.get("receiptId",""))==receipt_id and bool(row.get("actualDelivered",false)) and int(row.get("deliveredCount",0))>0: return true
		return false,12.0)
	check(delivered,"Reward actually delivers; queued/active alone cannot pass")
	if not alive(): return
	evidence.correctReward["eventsAfterReturn"] = events.slice(before).filter(func(row: Dictionary): return str(row.get("type",""))=="learning-reward-receipt" and str(row.get("receipt",{}).get("receiptId",""))==receipt_id)
	evidence.correctReward["receipts"] = app.game.snapshot().get("learningRewardReceipts",[])
	reward_panel_audit(receipt_id,"1280x800")
	await capture("actual-reward-delivery-1280x800")
	if not alive(): return
	await resize(Vector2i(1440,900))
	if not alive(): return
	reward_panel_audit(receipt_id,"1440x900")
	await capture("actual-reward-delivery-1440x900")
	if not alive(): return
	visible_ui_audit(app.ui,"reward-delivery")

func reward_panel_audit(receipt_id: String, label_value: String) -> void:
	if not alive(): return
	var panel: Control=named_control(app.ui,"LearningRewardReceipts")
	if not check(is_instance_valid(panel) and panel.is_visible_in_tree(),label_value+": actual reward notice is visible"): return
	var rows: Array=panel.get_meta("actualReceipts",[])
	var matching: Array=rows.filter(func(row: Dictionary): return str(row.get("receiptId",""))==receipt_id and bool(row.get("actualDelivered",false)) and int(row.get("deliveredCount",0))>0)
	check(not matching.is_empty(),label_value+": large notice represents this actual delivered receipt")
	check(panel.size.x>=300 and panel.size.y>=60 and root.get_visible_rect().encloses(panel.get_global_rect()),label_value+": reward notice is large and fully inside viewport")
	evidence.correctReward["panel"+label_value]={"bounds":str(panel.get_global_rect()),"actualReceipts":rows.duplicate(true)}

func learning_choice_audit(label_value: String) -> void:
	if not alive(): return
	visible_ui_audit(app.learning_field,"learning-"+label_value)
	var rows: Array=[]
	for target in app.learning_field.find_children("LearningTarget_*","Control",true,false):
		var image: Control=named_control(target,"DestinationImage")
		var action: Control=named_control(target,"DestinationAction")
		check(is_instance_valid(image) and image.size.x>=100 and image.size.y>=70,label_value+": learning choice has a large destination image")
		check(visible_clip(target).grow(1).encloses(target.get_global_rect()),label_value+": full learning choice fits without clipping")
		rows.append({"target":str(target.name),"bounds":str(target.get_global_rect()),"imageBounds":str(image.get_global_rect()) if is_instance_valid(image) else "missing","actionBounds":str(action.get_global_rect()) if is_instance_valid(action) else "missing"})
	check(not rows.is_empty(),label_value+": learning destination cards exist")
	if not evidence.has("learningChoices"): evidence["learningChoices"]={}
	evidence.learningChoices[label_value]=rows

func percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty(): return null
	var sorted: Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size())*fraction)-1,0,sorted.size()-1)]

func performance_summary() -> Dictionary:
	var times: Array = []
	var calls: Array = []
	var gpu: Array = []
	var friendly: Array = []
	var enemies: Array = []
	for row in frame_rows:
		times.append(row.frameMs); calls.append(row.drawCalls); friendly.append(row.friendly); enemies.append(row.enemies)
		if row.gpuMs != null: gpu.append(row.gpuMs)
	return {"targetWallSeconds":PERFORMANCE_SECONDS,"eligibleWallSeconds":eligible_wall_seconds,"frames":times.size(),"frameP50Ms":percentile(times,.5),"frameP95Ms":percentile(times,.95),"over50ms":times.filter(func(value): return float(value)>50.0).size(),"drawCallsP50":percentile(calls,.5),"drawCallsP95":percentile(calls,.95),"friendlyMin":friendly.min() if not friendly.is_empty() else null,"friendlyMax":friendly.max() if not friendly.is_empty() else null,"enemyMin":enemies.min() if not enemies.is_empty() else null,"enemyMax":enemies.max() if not enemies.is_empty() else null,"gpuStatus":"available_root_viewport_async" if not gpu.is_empty() else "unavailable_nonpositive_API_return","gpuP50Ms":percentile(gpu,.5),"gpuP95Ms":percentile(gpu,.95),"scope":"One bounded12second natural real-time combat window at1440x900, before automatic contextual learning. Actual current VSync and FPS limits retained. Screenshots, resize, selection, pause and learning excluded at both interval endpoints. No20second or full-game60FPS claim; first-run results retained separately."}

func capture_action_sequence() -> void:
	phase="action_sequence_after_performance"
	await buffered_motion("action",48,2)

func visible_ui_audit(parent: Node, label_value: String) -> void:
	if not is_instance_valid(parent): return
	var rows: Array=[]
	var view: Rect2=root.get_visible_rect()
	for node in parent.find_children("*","Control",true,false):
		if not node.is_visible_in_tree(): continue
		if node is Button:
			var inside: bool=view.grow(1).encloses(node.get_global_rect())
			rows.append({"path":str(node.get_path()),"text":node.text,"rect":str(node.get_global_rect()),"clip":str(visible_clip(node)),"disabled":node.disabled,"insideViewport":inside})
			if visible_clip(node).intersects(node.get_global_rect()): check(inside,label_value+": visible button fits viewport: "+str(node.name))
		if node is Label and str(node.name).contains("Heading"):
			check(not node.text.contains("3·5·8") and not node.text.contains("3/5/8") and not node.text.contains("358"),label_value+": no permanent generic 358 skill heading")
		if node.has_method("get_text_layout"):
			var word: Variant=node.get("word")
			if word is Dictionary and not str(word.get("jp","")).is_empty() and not str(word.get("ko","")).is_empty() and bool(node.get("meaning_visible")):
				paired_text_check(node.get_text_layout(),word,node.get_global_transform_with_canvas(),visible_clip(node),label_value+"/"+str(node.name))
	if not evidence.has("visibleUI"): evidence["visibleUI"]={}
	evidence.visibleUI[label_value]={"buttons":rows,"scope":"Actual visible control bounds/text runs; inspect full PNG for glyph/background overlap and occlusion."}

func named_id(parent: Node, name_value: String) -> int:
	var value: Control=named_control(parent,name_value)
	return value.get_instance_id() if is_instance_valid(value) and value is Button else 0

func home_review() -> void:
	phase="home_ui"
	await capture("home-1440x900")
	if not alive(): return
	for name_value in ["HomeSortie","HomeBarracks","HomeTraining","HomeDictionary"]:
		var id: int=named_id(app.front_end,name_value)
		var button: Button=live_button(id)
		if button==null: check(false,"Home menu control exists: "+name_value);continue
		var point: Vector2=button.get_global_rect().get_center()
		button=null
		var probe: Dictionary=await observe_single_motion(id,point,"home-"+name_value)
		if not alive(): return
		check(bool(probe.processedHit),"Home menu synthetic hover owns expected control: "+name_value)
	visible_ui_audit(app.front_end,"home-1440")
	if not await click_id(named_id(app.front_end,"HomeBarracks"),"Home barracks first click"): return
	if not check(await wait_until(func(): return alive() and app.barracks.visible,2.0),"Actual Home opens barracks"): return
	await capture("barracks-actual-starter-1440x900")
	if not alive(): return
	barracks_audit(app.barracks,"actual-starter")
	await resize(Vector2i(1280,800))
	if not alive(): return
	await capture("barracks-actual-starter-1280x800")
	if not alive(): return
	barracks_audit(app.barracks,"actual-starter-1280")
	if not await click_id(named_id(app.barracks,"BarracksBack"),"Actual barracks return first click"): return
	await resize(Vector2i(1440,900))
	if not alive(): return
	await capture("home-return-1440x900")
	if not alive(): return

func barracks_audit(panel: Node, label_value: String) -> void:
	visible_ui_audit(panel,"barracks-"+label_value)
	var cards: Array=panel.find_children("SkillCard_*","Control",true,false)
	check(cards.size()==3,label_value+": exactly three common skill cards exist")
	for card in cards:
		check(card.is_visible_in_tree() and visible_clip(card).grow(1).encloses(card.get_global_rect()),label_value+": each skill card is fully visible without scroll: "+str(card.name))
	for name_value in ["BarracksCurrency","CommanderLevel","CommanderUnitRole","ProductionAndUnlocks","ArmyDefenseStats"]:
		var value: Control=named_control(panel,name_value)
		if is_instance_valid(value): check(visible_clip(value).grow(1).encloses(value.get_global_rect()),label_value+": required detail fits: "+name_value)
	var bounds: Array=[]
	for name_value in ["CommanderUnitName","CommanderLevel","CommanderUnitRole","CommanderSkillList","ProductionAndUnlocks","ArmyDefenseStats"]:
		var value: Control=named_control(panel,name_value)
		if is_instance_valid(value) and value.is_visible_in_tree(): bounds.append({"name":name_value,"rect":value.get_global_rect()})
	for a in range(bounds.size()):
		for b in range(a+1,bounds.size()): check(not Rect2(bounds[a].rect).intersects(Rect2(bounds[b].rect)),label_value+": detail blocks do not overlap: "+str(bounds[a].name)+"/"+str(bounds[b].name))
	var preview: Variant=panel.get("unit_preview")
	if is_instance_valid(preview) and preview.has_method("diagnostics"):
		var data: Dictionary=preview.diagnostics()
		var renderer: Variant=preview.get("painted_renderer")
		var assets: Dictionary=renderer.diagnostics() if is_instance_valid(renderer) else {}
		data["paintedAssets"]=assets
		check(str(data.get("renderMode",""))=="painted2d" and bool(data.get("ready",false)) and str(assets.get("manifest",""))=="res://assets/characters/painted-v1/manifest.json",label_value+": portrait uses current painted assets")
		if not evidence.has("barracksPortraits"): evidence["barracksPortraits"]={}
		evidence.barracksPortraits[label_value]=data

func independent_ui_fixtures() -> void:
	# Separate in-memory account; no write_save/read_save, no main account edits.
	phase="explicit_ui_fixture"
	if not alive(): return
	if live_battle():
		if not await click_id(property_button_id("pause_button"),"Pause natural battle before separate UI fixtures"): return
	if not check(app.game.paused,"Main simulation is paused during explicit UI fixtures"): return
	var main_account_before: String=JSON.stringify(app.progress.data)
	app.ui.hide()
	var account: RefCounted=load("res://native/progress.gd").new()
	account.save_path="user://NEVER-WRITE-fix01-fixture.json"
	for index in range(40): account.data.maps["qa-fixture-"+str(index)]={"cleared":true}
	var panel: Control=load("res://native/barracks.gd").new()
	panel.progress=account
	panel.font=app.font
	panel.selected_unit_id="ninja"
	root.add_child(panel)
	var panel_id: int=panel.get_instance_id()
	panel.open(false,false)
	panel=null
	await settle(4)
	if not alive(): return
	await capture("FIXTURE-ninja-three-cards-1440x900")
	if not alive(): return
	var live_panel: Variant=instance_from_id(panel_id)
	if is_instance_valid(live_panel): barracks_audit(live_panel,"FIXTURE-ninja")
	live_panel=null
	await resize(Vector2i(1280,800))
	if not alive(): return
	await capture("FIXTURE-ninja-three-cards-1280x800")
	if not alive(): return
	live_panel=instance_from_id(panel_id)
	if is_instance_valid(live_panel):
		barracks_audit(live_panel,"FIXTURE-ninja-1280")
		live_panel.queue_free()
	live_panel=null
	await settle(2)
	if not alive(): return
	var training: Control=load("res://native/unit_training.gd").new()
	root.add_child(training)
	training.configure(null,app.maps,app.font)
	var training_id: int=training.get_instance_id()
	training.open_menu("spear")
	training=null
	await settle(4)
	if not alive(): return
	await capture("FIXTURE-training-current-roster-1280x800")
	if not alive(): return
	var drill: Variant=instance_from_id(training_id)
	if is_instance_valid(drill):
		visible_ui_audit(drill,"FIXTURE-training-roster")
		var portraits: Array=[]
		for portrait in drill.find_children("TrainingUnitPreview_*","Control",true,false):
			if not portrait.has_method("diagnostics"): continue
			var sample: Dictionary=portrait.diagnostics()
			var renderer: Variant=portrait.get("painted_renderer")
			var assets: Dictionary=renderer.diagnostics() if is_instance_valid(renderer) else {}
			sample["paintedAssets"]=assets
			check(str(sample.get("renderMode",""))=="painted2d" and bool(sample.get("ready",false)) and str(assets.get("manifest",""))=="res://assets/characters/painted-v1/manifest.json","Training roster portrait uses current painted assets: "+str(portrait.name))
			portraits.append({"name":str(portrait.name),"bounds":str(portrait.get_global_rect()),"clip":str(visible_clip(portrait)),"diagnostics":sample})
		check(portraits.size()==7,"Current seven friendly roster portraits are present")
		evidence["trainingRosterPortraits"]=portraits
	if not is_instance_valid(drill): incomplete.append("Fixture drill was freed");return
	var opened: bool=drill.open("spear",app.maps[0])
	check(opened,"Explicit isolated fixture opens current spear drill")
	drill=null
	await settle(4)
	if not alive(): return
	drill=instance_from_id(training_id)
	if not is_instance_valid(drill): return
	var button_id: int=drill.action_button.get_instance_id() if is_instance_valid(drill.action_button) else 0
	drill=null
	await capture("FIXTURE-spear-practice-ready-1280x800")
	if not alive(): return
	if await click_id(button_id,"Fixture drill actual deploy first click"):
		await wait_until(func():
			var value: Variant=instance_from_id(training_id)
			return is_instance_valid(value) and int(value.observations.get("hits",0))>0,15.0)
		await capture("FIXTURE-spear-practice-actual-1280x800")
		if not alive(): return
	drill=instance_from_id(training_id)
	if is_instance_valid(drill):
		var state: Dictionary=drill.diagnostics()
		check(str(state.get("renderMode",""))=="painted2d" and bool(state.get("trainingOnly",false)),"Fixture drill uses current painted2D and stays training-only")
		check(int(drill.observations.get("hits",0))>0,"Fixture practice produces a real drill hit; no campaign unlock claim")
		evidence["uiFixture"]={"scope":"Explicit separate in-memory all-unlocked barracks and null-account drill. NOT earned unlocks, natural campaign or saved progress.","drill":state,"mainAccountUnchanged":main_account_before==JSON.stringify(app.progress.data)}
		drill.queue_free()
	drill=null
	check(main_account_before==JSON.stringify(app.progress.data),"UI fixtures leave Main account data unchanged")
	app.ui.show()

func buffered_motion(label_value: String, count: int, stride: int) -> void:
	measuring = false
	measurement_epoch += 1
	var frames: Array = []
	var images: Array[Image] = []
	var prior_clock: float = app.game.elapsed if alive() else -1.0
	var stop_reason: String = "complete"
	evidence[label_value+"Sequence"]={"frames":frames,"stopReason":"collecting","requestedFrames":count,"scope":"Actual live advancing-clock full viewports; PNG writes deferred. GPU readback costs remain; no speed/performance claim. Visual rig/contact review required."}
	capture_buffers[label_value]={"frames":frames,"images":images}
	for index in range(count):
		await settle(stride)
		if not live_battle(): stop_reason="not_live_battle";break
		var clock: float = app.game.elapsed
		if clock<=prior_clock: stop_reason="clock_not_advancing";break
		prior_clock=clock
		images.append(root.get_texture().get_image())
		var actors: Array=[]
		for actor in app.game.units+app.game.enemies:
			var friendly: bool=actor.has("type")
			var key: String=("friendly/" if friendly else "enemy/")+str(actor.id)
			actors.append({"key":key,"type":actor.get("type",actor.get("kind","")),"position":str(actor.position),"screenFoot":str(app.game.field_point_to_screen(actor.position)),"state":str(actor.get("animation","")),"animationClock":actor.get("animationClock",0),"source":app.game.painted_actors.actor_samples.get(key,{}).duplicate(true),"foreground":foreground_actor_observation(actor,friendly)})
		frames.append({"clock":clock,"wallSeconds":wall_seconds(),"actors":actors,"contactTracks":app.game.painted_actors.get("_contact_tracks").duplicate(true),"state":destination_snapshot(),"path":ProjectSettings.globalize_path(output_dir.path_join("%s-%02d.png" % [label_value,index]))})
	# All readbacks precede PNG writes. Readback still costs time; this is motion
	# evidence, never a natural-performance or real-time speed measurement.
	flush_motion_buffer(label_value)
	if stopped: return
	evidence[label_value+"Sequence"]["stopReason"]=stop_reason
	check(frames.size()==count,label_value+": requested live advancing-clock frames collected")
	if frames.size()!=count: incomplete.append(label_value+" sequence partial: "+stop_reason)
	journal("motion_sequence",{"label":label_value,"frames":frames.size(),"stopReason":stop_reason})
	measurement_epoch += 1

func foreground_actor_observation(actor: Dictionary, friendly: bool) -> Dictionary:
	var point: Vector2=actor.position
	var foot: Vector2=app.game._screen(point)
	var height: float=app.game.painted_actors.body_height_screen*clampf(app.game.field_rect.size.y/620.0,.65,1.5)
	var rows: Array=[]
	for clip in app.game.find_children("ForegroundClip_*","Control",true,false):
		if not clip.is_visible_in_tree() or clip.get_child_count()==0: continue
		var patch: Node=clip.get_child(0)
		var data: Dictionary=patch.get("data")
		var rect: Rect2=patch.get("patch_rect")
		rows.append({"id":str(data.get("id","")),"baseline":data.get("baseline",null),"frontEligible":point.y>=float(data.get("baseline",2)) and rect.grow(height*2).has_point(foot),"battleCanvasFoot":str(foot),"frontLocalFoot":str(foot-rect.position),"patchRect":str(rect),"clipGlobalRect":str(clip.get_global_rect()),"baselineDelta":point.y-float(data.get("baseline",2))})
	return {"actorKey":("friendly/" if friendly else "enemy/")+str(actor.id),"scope":"Read-only same-ID main/front coordinate evidence. Eligibility is observed, not proof of a rendered front pass or visual acceptance.","patches":rows}

func flush_motion_buffer(label_value: String) -> void:
	if not capture_buffers.has(label_value): return
	var buffer: Dictionary=capture_buffers[label_value]
	for index in range(buffer.images.size()):
		var error: int=buffer.images[index].save_png(str(buffer.frames[index].path))
		buffer.frames[index]["saveError"]=error
		check(error==OK,"Buffered full viewport PNG saves: %s/%d" % [label_value,index])
	buffer.images.clear()
	capture_buffers.erase(label_value)

func finish(reason: String = "complete") -> void:
	if stopped: return
	for label_value in capture_buffers.keys():
		evidence[str(label_value)+"Sequence"]["stopReason"]=reason
		flush_motion_buffer(str(label_value))
	stopped = true
	observing = false
	measuring = false
	var ingress_success: bool = false
	for trace in ingress.values():
		if bool(trace.firstOutsideMap) and bool(trace.enteredMap): ingress_success = true
	var hits: Array = events.filter(func(event: Dictionary): return str(event.get("type",""))=="hit" and str(event.get("side",""))=="friendly" and float(event.get("damage",0))>0 and float(event.get("hpBefore",0))>float(event.get("hpAfter",0)))
	if reason != "setup_rejected":
		check(ingress_success,"The same observed enemy ID travels from outside the map into visible approach")
		check(not hits.is_empty(),"Natural friendly attacks produce real enemy HP loss")
		check(eligible_wall_seconds>=PERFORMANCE_SECONDS-.05,"Twelve seconds of eligible natural combat frames were measured")
		check(int(destination_visits.study)==1,"The manual study destination was opened exactly once")
		check(int(destination_visits.context)>=2,"Separate natural automatic skip and correct-answer destinations were observed")
	evidence["hoverProbes"] = hover_probes
	evidence["destinationVisits"] = destination_visits
	evidence["actualActionTrace"] = action_trace
	var real_releases: Array=action_trace.filter(func(row: Dictionary): return str(row.sample.get("sourceState",""))=="attack" and int(row.sample.get("releaseFrame",-1))>=0 and int(row.sample.get("sourceFrame",-1))==int(row.sample.get("releaseFrame",-2)) and bool(row.sample.get("releaseCommitted",false)) and not bool(row.sample.get("previewTiming",true)))
	if reason=="complete": check(not real_releases.is_empty(),"Actual rendered actors reach authored release frames tied to real combat events")
	evidence["actualAuthoredReleaseCount"]=real_releases.size()
	evidence["sourcesAtEnd"]=hash_sources()
	check(source_hashes==evidence.sourcesAtEnd,"Source/asset hashes remain unchanged during this run")
	evidence["inputRoute"]={"pointer":"Viewport.push_input(event,true)","coordinateSpace":"viewport local","nativeCursorWarped":false,"noTouchMouseRemapping":true,"reference":"https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-push-input","nativeMouseMismatchIsSeparateObservation":true}
	evidence["observations"]=observations
	var report: Dictionary = {"status":"passed" if failures.is_empty() and incomplete.is_empty() and reason=="complete" else "partial_or_failed","visualAcceptance":"pending_HQ_original_PNG_review","reason":reason,"wallSeconds":wall_seconds(),"checks":check_rows,"failures":failures,"incomplete":incomplete,"captures":captures,"paidOrders":paid_orders,"clicks":clicks,"inputTrace":input_trace,"enemyIngress":ingress,"events":events,"realDamageEvents":hits,"performance":performance_summary(),"frameRows":frame_rows,"evidence":evidence,"sources":source_hashes,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"displayServer":DisplayServer.get_name(),"vsyncMode":DisplayServer.window_get_vsync_mode(),"engineMaxFps":Engine.max_fps,"engineLaunchesThisScript":1,"automaticSecondClick":false,"directGameplayStateMutation":false}
	if is_instance_valid(app) and is_instance_valid(app.get("game")):
		report["finalBattle"] = {"clock":app.game.elapsed,"gold":app.game.gold,"friendly":app.game.units.size(),"enemies":app.game.enemies.size(),"kills":app.game.kills,"paused":app.game.paused,"finished":app.game.finished}
		for property_name in ["painted_field","painted_actors"]:
			var value: Variant = app.game.get(property_name)
			if is_instance_valid(value) and value.has_method("diagnostics"): report[property_name] = value.diagnostics()
	if not output_dir.is_empty():
		var diagnostics_file: FileAccess = FileAccess.open(output_dir.path_join("ui-and-foot-diagnostics.json"),FileAccess.WRITE)
		if diagnostics_file != null:
			diagnostics_file.store_string(JSON.stringify({"briefing":evidence.get("briefing",{}),"compactUI":evidence.get("compactUI",{}),"hoverProbes":hover_probes,"destinationVisits":destination_visits,"selection":evidence.get("selection",{}),"selectedTranslation":evidence.get("selectedTranslation",{}),"footGrounding":evidence.get("footGrounding",{}),"roadOverlay":evidence.get("roadOverlay",{}),"captures":captures,"scope":"UI geometry/framebuffer proxies and foot registration diagnostics; visible art/sole acceptance requires inspecting normal engine captures. QA overlay is analysis-only."},"  "))
			diagnostics_file.close()
		var file: FileAccess = FileAccess.open(output_dir.path_join("report.json"),FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report,"  ")); file.close()
		var latest: FileAccess = FileAccess.open(OUTPUT_ROOT.path_join("latest.json"),FileAccess.WRITE)
		if latest != null: latest.store_string(JSON.stringify({"report":ProjectSettings.globalize_path(output_dir.path_join("report.json")),"status":report.status,"captures":captures},"  ")); latest.close()
	print("PAINTED_GAME_RESULT ",JSON.stringify({"status":report.status,"reason":reason,"report":ProjectSettings.globalize_path(output_dir.path_join("report.json")),"failures":failures,"performance":report.performance}))
	if is_instance_valid(app): app.queue_free()
	quit(0 if report.status=="passed" else 1)

func run() -> void:
	started = Time.get_ticks_usec()
	var evidence_root: String = canonical(ProjectSettings.globalize_path(OUTPUT_ROOT))
	var profile: String = canonical(ProjectSettings.globalize_path("user://"))
	if not check(profile.begins_with(evidence_root+"/") and DisplayServer.get_name()!="headless","Rendered engine uses the isolated painted-game profile"):
		finish("setup_rejected")
		return
	output_dir = OUTPUT_ROOT.path_join("run-"+str(int(Time.get_unix_time_from_system())))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var previous_reports: Array = []
	for prior_path in [FIRST_RUN_REPORT,INPUT_FAILURE_REPORT,SINGLE_FRAME_HOVER_REPORT]:
		previous_reports.append({"path":ProjectSettings.globalize_path(prior_path),"sha256":FileAccess.get_sha256(prior_path) if FileAccess.file_exists(prior_path) else "missing"})
	evidence["observerCorrection"] = {"priorReports":previous_reports,"reason":"All earlier reports remain intact. This revision observes one motion immediately and over the next two rendered frames, including viewport mouse position. First null owners remain evidence; processed misses still fail. No pointer redispatch or second click is used for these probes. Actual text runs now verify adjacent Japanese/Korean placement, with hidden combat-name states identified explicitly.","revision":"single-motion-temporal-hover-and-paired-translation"}
	create_timer(MAX_SECONDS).timeout.connect(func():
		if not stopped:
			incomplete.append("Hard240second deadline reached during "+phase)
			finish("deadline")
	)
	source_hashes=hash_sources()
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	app = load("res://native/main.tscn").instantiate()
	app.progress.save_path = "user://painted-game-"+str(int(Time.get_unix_time_from_system()))+".json"
	if not check(not FileAccess.file_exists(app.progress.save_path),"A fresh isolated player file is used without editing account data"):
		finish("setup_rejected"); return
	root.add_child(app)
	await settle(3)
	if not alive(): return
	check(app.front_end.visible and str(app.front_end.view)=="home","Actual Main begins on Home")
	await home_review()
	if not alive(): return
	if not check(app.front_end.visible and not app.barracks.visible,"Home is restored after real menu review"):
		finish("home_menu_failed");return
	app.game.game_event.connect(on_event)
	observing = true
	call_deferred("observe_frames")
	phase = "home_enter"
	await key_enter()
	if not alive(): return
	var briefing_ready: bool = await wait_until(func(): return alive() and app.modal!=null and str(app.modal_context)=="briefing" and not app.front_end.visible,12.0)
	if not alive(): return
	if not check(briefing_ready,"One actual Home Enter opens the first mission briefing"):
		await capture("failed-enter-destination"); finish("entry_failed"); return
	phase = "briefing"
	var arrival_ready: bool = await wait_until(func(): return alive() and (not is_instance_valid(app.scene_transition) or not app.scene_transition.is_running()) and (not is_instance_valid(app.transition_layer) or not app.transition_layer.is_visible_in_tree()),3.0)
	if not alive(): return
	check(arrival_ready,"Normal scene-arrival animation finishes and its overlay hides before the mission capture")
	if not alive(): return
	evidence["briefingSceneReadiness"] = {"ready":arrival_ready,"clock":app.game.elapsed,"transitionRunning":app.scene_transition.is_running() if is_instance_valid(app.scene_transition) else false,"overlayVisible":app.transition_layer.is_visible_in_tree() if is_instance_valid(app.transition_layer) else false,"overlayAlpha":app.transition_layer.modulate.a if is_instance_valid(app.transition_layer) else null}
	await settle(3)
	if not alive(): return
	await capture("mission-briefing-1440x900")
	if not alive(): return
	briefing_check("1440x900")
	await resize(Vector2i(1280,800))
	if not alive(): return
	await capture("mission-briefing-1280x800")
	if not alive(): return
	briefing_check("1280x800")
	await resize(Vector2i(1440,900))
	if not alive(): return
	var confirm: Control = named_control(app.modal,"ConfirmMission")
	var confirm_id: int = confirm.get_instance_id() if is_instance_valid(confirm) else 0
	confirm = null
	await click_id(confirm_id,"Mission confirm first click")
	if not alive(): return
	var ready: bool = await wait_until(func(): return alive() and app.battle_started and app.game.running and not app.front_end.visible and app.modal == null,5.0)
	if not alive(): return
	if not check(ready,"One actual mission confirmation click reaches the running first battle"):
		await capture("failed-confirm-destination"); finish("entry_failed"); return
	phase = "readiness_capture"
	await capture("ready-1440x900")
	if not alive(): return
	evidence["hud1440"] = hud_evidence()
	await compact_ui_check("ready-1440x900")
	if not alive(): return
	check(bool(app.game.config.get("paintedPresentation",false)) and not app.game.three_d_enabled,"Actual first battle mounts the painted2D mode")
	var old_troops: Variant = app.get("troops_3d")
	var old_world_created: bool = is_instance_valid(old_troops) and (is_instance_valid(old_troops.get("viewport")) or is_instance_valid(old_troops.get("world")) or is_instance_valid(old_troops.get("camera")))
	check(not old_world_created,"No old3D troop viewport, world or camera is initialized")
	evidence["threeDNodesAtBattleReady"] = root.find_children("*","Node3D",true,false).size()
	evidence["subViewportsAtBattleReady"] = root.find_children("*","SubViewport",true,false).size()
	for renderer_name in ["painted_field","painted_actors"]:
		var renderer: Variant = app.game.get(renderer_name)
		check(is_instance_valid(renderer) and renderer.has_method("is_ready") and bool(renderer.is_ready()),"Actual painted renderer is ready: "+renderer_name)
	await resize(Vector2i(1280,800))
	if not alive(): return
	await capture("ready-1280x800")
	if not alive(): return
	evidence["hud1280"] = hud_evidence()
	await compact_ui_check("ready-1280x800")
	if not alive(): return
	await resize(Vector2i(1440,900))
	if not alive(): return
	phase = "paid_placement"
	var starting_gold: int=app.game.gold
	if not await drag_archer("left-shoulder-pad"):
		finish("first_archer_input_failed");return
	if not alive(): return
	if alive() and app.game.gold>=app.game.recruit_cost("archer")+app.game.recruit_cost("spear"):
		if not await drag_archer("right-shoulder-pad"):
			finish("second_archer_input_failed");return
		if not alive(): return
	else:
		incomplete.append("Natural gold cannot pay a second archer while retaining the spear order")
	if not await spear_order():
		finish("first_spear_input_failed");return
	if not alive(): return
	# Extra starter orders are paid from the untouched wallet. New crowd telemetry
	# records actual actor counts; it never substitutes the older 3-vs-8 sample.
	for unused in range(4):
		if alive() and app.game.gold>=app.game.recruit_cost("spear"):
			if not await spear_order():
				finish("paid_spear_input_failed");return
	if not alive(): return
	evidence["naturalProductionPreviews"]=app.game.production_preview_snapshot().duplicate(true)
	await capture("natural-production-ghosts-1440x900")
	if not alive(): return
	check(named_control(app.ui,"ProductionGauge")==null,"Old generic ProductionGauge is absent")
	evidence["productionCards"]=app.ui.find_children("RecruitmentJob_*","Control",true,false).map(func(node: Control): return {"name":str(node.name),"bounds":str(node.get_global_rect()),"visible":node.is_visible_in_tree()})
	check(await wait_until(func(): return alive() and app.game.recruitment_queue.is_empty() and app.game.units.size()>0,6.0),"Paid units finish production through natural elapsed time")
	if not alive(): return
	var archers: int=app.game.units.filter(func(unit: Dictionary): return str(unit.type)=="archer").size()
	var spears: int=app.game.units.filter(func(unit: Dictionary): return str(unit.type)=="spear").size()
	check(starting_gold==280 and archers>=2 and spears>=5,"Untouched natural wallet280 recruits two archers and at least five spears")
	evidence["postProduction"] = {"clock":app.game.elapsed,"units":app.game.units.size(),"gold":app.game.gold,"startingGold":starting_gold,"paidCost":paid_orders.reduce(func(total: int,row: Dictionary): return total+int(row.goldBefore)-int(row.goldAfter),0),"archers":archers,"spears":spears}
	evidence["shootingPositions"]=app.game.shooting_position_snapshot()
	check(evidence.shootingPositions.size()==8 and evidence.shootingPositions.all(func(row: Dictionary): return int(row.slotCapacity)==2),"Natural stage exposes eight shared two-slot firing positions")
	await capture("paid-units-1440x900")
	if not alive(): return
	await selection_check()
	if not alive(): return
	await pause_and_learning()
	if not alive(): return
	if not check(not app.game.paused and not app.context_task_active and app.modal == null,"Battle controls finish before the natural combat observation"):
		incomplete.append("Natural performance and automatic learning checks stopped after an unresolved control destination; no repeated click")
		finish("control_destination_failed")
		return
	phase = "ingress_capture"
	var visible_ingress: bool = await wait_until(func(): return not visible_ingress_enemy().is_empty(),3.0)
	if not alive(): return
	check(visible_ingress,"A previously offscreen enemy reaches the actual visible approach before performance sampling")
	evidence["ingressCapture"] = visible_ingress_enemy()
	await capture("ingress-and-map-feet-1440x900")
	if not alive(): return
	phase = "natural_combat"
	measurement_epoch += 1
	measuring = true
	var performance_start: int = Time.get_ticks_usec()
	var performance_clock: float = app.game.elapsed
	while alive() and eligible_wall_seconds<PERFORMANCE_SECONDS and Time.get_ticks_usec()-performance_start<18000000:
		if app.context_task_active or app.game.between_waves or app.game.paused or app.modal != null:
			incomplete.append("Natural combat window ended at an actual learning/pause destination before its12second target")
			break
		await process_frame
		if not alive(): return
	measuring = false
	measurement_epoch += 1
	if not alive(): return
	evidence["naturalWindow"] = {"startBattleClock":performance_clock,"endBattleClock":app.game.elapsed,"wallSeconds":float(Time.get_ticks_usec()-performance_start)/1000000.0,"targetEligibleSeconds":PERFORMANCE_SECONDS,"eligibleWallSeconds":eligible_wall_seconds,"automaticContextOpen":app.context_task_active}
	check(not app.context_task_active and app.modal == null and not app.game.between_waves,"Immediate combat capture precedes the automatic learning screen")
	await capture("natural-combat-1440x900")
	if not alive(): return
	foot_registration_diagnostics("natural-combat-1440x900")
	phase = "combat_capture_1280"
	await resize(Vector2i(1280,800))
	if not alive(): return
	await capture("natural-combat-1280x800")
	if not alive(): return
	selected_translation_check("natural-combat-1280x800")
	await automatic_learning_return()
	if not alive(): return
	if not live_battle():
		finish("automatic_learning_unresolved");return
	if not alive(): return
	phase = "final_capture"
	await capture("final-1280x800")
	if not alive(): return
	foot_registration_diagnostics("final-1280x800")
	await road_overlay_capture()
	if not alive(): return
	await independent_ui_fixtures()
	if not alive(): return
	finish()
